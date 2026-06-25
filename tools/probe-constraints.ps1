<#
.SYNOPSIS
    flux - constraint probing against the Panorama XML-API.

.DESCRIPTION
    Sends deliberately *invalid* `set` calls and records whether/how PAN-OS rejects them
    at set time. From this we derive which constraints are enforced at set time vs commit
    time (see schema/constraints/probe-results.md).

    Idempotent: temporary `flux-probe*` objects are deleted again after the test.
    No commit is performed.

.EXAMPLE
    $env:PAN_HOST='192.168.99.2'; $env:PAN_USER='admin'; $env:PAN_PASSWORD='***'
    .\tools\probe-constraints.ps1
#>
[CmdletBinding()]
param(
    [string]$PanHost  = $env:PAN_HOST,
    [string]$User     = $env:PAN_USER,
    [string]$Password = $env:PAN_PASSWORD
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pan-api.ps1')
$null = Connect-Pan -PanHost $PanHost -User $User -Password $Password

$DEV  = "/config/devices/entry[@name='localhost.localdomain']"
$DG   = "$DEV/device-group/entry[@name='flux-dg']"
$TCFG = "$DEV/template/entry[@name='flux-tpl']/config/devices/entry[@name='localhost.localdomain']"

# Context for the template-interior probes (deleted at the end). The reference probes
# below deliberately point at a NONEXISTENT interface (ethernet9/9) to show that PAN-OS
# checks interface references at set time.
$null = Invoke-PanConfig -Action set -XPath "$DEV/template/entry[@name='flux-tpl']" -Element '<description>flux probe tpl</description>'

$probes = @(
    @{ label='rule action invalid enum'; expect='reject';
       xpath="$DG/pre-rulebase/security/rules/entry[@name='flux-probe']"; element='<action>foobar</action>' }
    @{ label='address unknown child';     expect='reject';
       xpath="/config/shared/address/entry[@name='flux-probe']"; element='<bogus>x</bogus>' }
    @{ label='address invalid ipv4';      expect='reject';
       xpath="/config/shared/address/entry[@name='flux-probe2']"; element='<ip-netmask>not-an-ip</ip-netmask>' }
    @{ label='service port out of range'; expect='reject';
       xpath="/config/shared/service/entry[@name='flux-probe-svc']"; element='<protocol><tcp><port>99999</port></tcp></protocol>' }
    @{ label='service port non-numeric';  expect='reject';
       xpath="/config/shared/service/entry[@name='flux-probe-svc2']"; element='<protocol><tcp><port>abc</port></tcp></protocol>' }
    @{ label='address missing type (only description)'; expect='accept-at-set';
       xpath="/config/shared/address/entry[@name='flux-probe3']"; element='<description>no type here</description>' }
    # --- NAT rule (device-group) ---
    @{ label='nat-rule nat-type invalid enum'; expect='reject';
       xpath="$DG/pre-rulebase/nat/rules/entry[@name='flux-probe-nat']"; element='<nat-type>bogus</nat-type>' }
    @{ label='nat-rule unknown child'; expect='reject';
       xpath="$DG/pre-rulebase/nat/rules/entry[@name='flux-probe-nat']"; element='<bogus>x</bogus>' }
    @{ label='nat-rule incomplete (only description)'; expect='accept-at-set';
       xpath="$DG/pre-rulebase/nat/rules/entry[@name='flux-probe-nat2']"; element='<description>missing from/to/...</description>' }
    # --- template-interior network config ---
    @{ label='interface unknown child'; expect='reject';
       xpath="$TCFG/network/interface/ethernet/entry[@name='ethernet1/9']"; element='<bogus/>' }
    @{ label='interface bad ip format (NOT set-enforced)'; expect='accept-at-set';
       xpath="$TCFG/network/interface/ethernet/entry[@name='ethernet1/9']"; element='<layer3><ip><entry name="not-an-ip"/></ip></layer3>' }
    @{ label='zone unknown child'; expect='reject';
       xpath="$TCFG/vsys/entry[@name='vsys1']/zone/entry[@name='flux-probe-z']"; element='<bogus/>' }
    @{ label='zone interface reference checked at set'; expect='reject';
       xpath="$TCFG/vsys/entry[@name='vsys1']/zone/entry[@name='flux-probe-z']"; element='<network><layer3><member>ethernet9/9</member></layer3></network>' }
    @{ label='virtual-router interface reference checked at set'; expect='reject';
       xpath="$TCFG/network/virtual-router/entry[@name='flux-probe-vr']"; element='<interface><member>ethernet9/9</member></interface>' }
)

$rows = foreach ($p in $probes) {
    $r = Invoke-PanConfig -Action set -XPath $p.xpath -Element $p.element
    $ok = Test-PanSuccess $r
    if ($ok) { $null = Invoke-PanConfig -Action delete -XPath $p.xpath }   # tidy up
    [pscustomobject]@{
        Probe   = $p.label
        Expect  = $p.expect
        Result  = if ($ok) { 'accepted' } else { "error code=$($r.response.code)" }
        Message = if ($ok) { '' } else { Get-PanError $r }
    }
}
$rows | Format-List

# tidy up the probe context (candidate only; no commit)
$null = Invoke-PanConfig -Action delete -XPath "$DEV/template/entry[@name='flux-tpl']"
$null = Invoke-PanConfig -Action delete -XPath $DG
