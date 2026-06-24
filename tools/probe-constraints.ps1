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

$DG = "/config/devices/entry[@name='localhost.localdomain']/device-group/entry[@name='flux-dg']"

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
