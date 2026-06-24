<#
.SYNOPSIS
    flux - compares the flux validator verdict with Panorama's OWN validation.

.DESCRIPTION
    "Panorama's own validation" has two layers:
      A) set/edit time -> blocks structure, unknown elements, enums, value formats immediately.
      B) validate full  -> the commit check: required fields, choice groups, references,
                           missing mandatory sub-nodes ('settings' etc.).
    Panorama rejects an object if A OR B rejects it. flux should match that union.

    Per case the object is isolated via targeted `delete` (NOT `revert`, which can leave the
    next `set` failing with "Could not copy parent object"). Prereq objects are (re)set first,
    then the object, then `validate full`; validation error lines are filtered by the object
    name, then compared to `tools/validate_config.py`.

.EXAMPLE
    $env:PAN_HOST='192.168.99.2'; $env:PAN_USER='admin'; $env:PAN_PASSWORD='***'
    .\tools\compare-validation.ps1
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

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fx   = Join-Path $root 'schema\fixtures'
$val  = Join-Path $root 'tools\validate_config.py'
$DEV  = "/config/devices/entry[@name='localhost.localdomain']"
$DG   = "$DEV/device-group/entry[@name='flux-dg']"
$SH   = "/config/shared"

function Invoke-ValidateFull {
    $v = Invoke-PanOp '<validate><full></full></validate>'
    $jobid = $v.response.result.job
    if (-not $jobid) { return @{ result='ENQUEUE-FAIL'; lines=@(Get-PanError $v) } }
    for ($i=0; $i -lt 80; $i++) {
        $j = Invoke-PanOp "<show><jobs><id>$jobid</id></jobs></show>"
        $job = $j.response.result.job
        if ($job.status -eq 'FIN') {
            $lines = @($job.SelectNodes('details/line') | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ })
            return @{ result=$job.result; lines=$lines }
        }
        Start-Sleep -Milliseconds 500
    }
    @{ result='TIMEOUT'; lines=@() }
}

# Prereq building blocks
$P_DG  = @{ xpath=$DG;                                       element='<description>flux demo dg</description>' }
$P_WEB = @{ xpath="$SH/address/entry[@name='flux-web-srv']"; element='<ip-netmask>10.10.10.10/32</ip-netmask>' }
$P_TPL = @{ xpath="$DEV/template/entry[@name='flux-tpl']";   element='<description>flux tpl</description>' }

# fixture supplies the element (inner XML); token = object name to filter validation errors
$cases = @(
  # --- valid ---
  @{ key='address (valid)';        fixture='shared_address.xml';       xpath="$SH/address/entry[@name='flux-web-srv']";       token='flux-web-srv'; prereqs=@() }
  @{ key='service (valid)';        fixture='shared_service.xml';       xpath="$SH/service/entry[@name='flux-tcp-8080']";      token='flux-tcp-8080'; prereqs=@() }
  @{ key='address-group (valid)';  fixture='shared_address_group.xml'; xpath="$SH/address-group/entry[@name='flux-web-grp']"; token='flux-web-grp'; prereqs=@($P_WEB) }
  @{ key='device-group (valid)';   fixture='device_group.xml';         xpath="$DG";                                          token='flux-dg'; prereqs=@() }
  @{ key='dg-address (valid)';     fixture='dg_address.xml';           xpath="$DG/address/entry[@name='flux-db-srv']";        token='flux-db-srv'; prereqs=@($P_DG) }
  @{ key='security-rule (valid)';  fixture='dg_security_rule.xml';     xpath="$DG/pre-rulebase/security/rules/entry[@name='flux-allow-web']"; token='flux-allow-web'; prereqs=@($P_DG,$P_WEB) }
  @{ key='template (valid)';       fixture='template.xml';             xpath="$DEV/template/entry[@name='flux-tpl']";         token='flux-tpl'; prereqs=@() }
  @{ key='template-stack (valid)'; fixture='template_stack.xml';       xpath="$DEV/template-stack/entry[@name='flux-stack']"; token='flux-stack'; prereqs=@($P_TPL) }
  # --- invalid ---
  @{ key='rule bad action/no to';  fixture='invalid\rule_bad_action_missing_to.xml'; xpath="$DG/pre-rulebase/security/rules/entry[@name='bad-rule']"; token='bad-rule'; prereqs=@($P_DG) }
  @{ key='address bad ip';         fixture='invalid\address_bad_ip.xml';       xpath="$SH/address/entry[@name='bad-ip']";    token='bad-ip'; prereqs=@() }
  @{ key='address unknown child';  fixture='invalid\address_unknown_child.xml';xpath="$SH/address/entry[@name='bad-child']"; token='bad-child'; prereqs=@() }
  @{ key='address no type';        fixture='invalid\address_no_type.xml';      xpath="$SH/address/entry[@name='no-type']";   token='no-type'; prereqs=@() }
  @{ key='service no port';        fixture='invalid\service_no_port.xml';      xpath="$SH/service/entry[@name='bad-svc']";   token='bad-svc'; prereqs=@() }
)

$rows = foreach ($c in $cases) {
    # delete-isolation: remove this object first (ignore result), then (re)set prereqs
    $null = Invoke-PanConfig -Action delete -XPath $c.xpath
    foreach ($p in $c.prereqs) { $null = Invoke-PanConfig -Action set -XPath $p.xpath -Element $p.element }

    [xml]$x = Get-Content -LiteralPath (Join-Path $fx $c.fixture) -Raw
    $element = $x.DocumentElement.InnerXml
    $setResp = Invoke-PanConfig -Action set -XPath $c.xpath -Element $element

    if (-not (Test-PanSuccess $setResp)) {
        $panos = 'REJECT'; $layer = 'set'; $detail = Get-PanError $setResp
    } else {
        $vr = Invoke-ValidateFull
        $hits = @($vr.lines | Where-Object { $_ -match [regex]::Escape($c.token) })
        if ($hits.Count -gt 0) { $panos = 'REJECT'; $layer = 'validate'; $detail = ($hits -join ' | ') }
        else { $panos = 'ACCEPT'; $layer = '-'; $detail = '' }
    }
    $null = Invoke-PanConfig -Action delete -XPath $c.xpath   # tidy up

    # flux verdict
    & python $val --xml (Join-Path $fx $c.fixture) --xpath $c.xpath *> $null
    $flux = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }

    $match = (($flux -eq 'FAIL') -eq ($panos -eq 'REJECT'))
    [pscustomobject]@{ Case=$c.key; flux=$flux; Panorama="$panos($layer)"; Match=$(if($match){'OK'}else{'MISMATCH'}); Detail=$detail }
}

$rows | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$mismatch = @($rows | Where-Object { $_.Match -eq 'MISMATCH' })
Write-Host ("`n{0}/{1} agree; {2} mismatch(es)." -f ($rows.Count-$mismatch.Count), $rows.Count, $mismatch.Count)
if ($mismatch.Count) { exit 1 } else { exit 0 }
