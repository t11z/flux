<#
.SYNOPSIS
    flux - schema compiler: builds schema/panorama-schema.json (single source of truth).

.DESCRIPTION
    Combines a curated resource model (required / enums / formats / references, derived
    from the constraint probing in schema/constraints/probe-results.md and the
    validate-full comparison) with the real structure from the fixtures
    (schema/fixtures/*.xml). The result is a compact, normalized JSON schema that
    tools/validate_config.py checks against.

    The schema is BOUND to a PAN-OS version: the version is read from
    schema/source-info.json (written by seed-fixtures.ps1 from the live box). A
    versioned archive copy is written to schema/versions/panorama-<version>.json.

    Also runs a consistency check: every element in a fixture MUST be a known
    allowedChild in the schema, so the schema stays tied to the live box.

    XML-API only. No REST source.

.EXAMPLE
    .\tools\build-schema.ps1
#>
[CmdletBinding()]
param(
    [string]$FixturesDir,
    [string]$OutFile,
    [string]$SourceInfo,
    [string]$PanosVersion
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty in the param() default under -File; resolve in the body.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
if (-not $FixturesDir) { $FixturesDir = Join-Path $here '..\schema\fixtures' }
if (-not $OutFile)     { $OutFile     = Join-Path $here '..\schema\panorama-schema.json' }
if (-not $SourceInfo)  { $SourceInfo  = Join-Path $here '..\schema\source-info.json' }

# Resolve the PAN-OS version this schema is bound to (live capture wins).
if (-not $PanosVersion) {
    if (Test-Path $SourceInfo) { $PanosVersion = (Get-Content $SourceInfo -Raw | ConvertFrom-Json).panosVersion }
}
if (-not $PanosVersion) { $PanosVersion = '0.0.0'; Write-Warning "No source-info.json; panosVersion defaulted to $PanosVersion. Run seed-fixtures.ps1 first." }

# Container XPaths are predicate-stripped (no [@name='...']); the validator
# normalizes input XPaths the same way before matching.
$DEV = "/config/devices/entry/device-group/entry"

$resources = [ordered]@{

    'address' = [ordered]@{
        containers      = @('/config/shared/address', "$DEV/address")
        allowedChildren = @('ip-netmask','ip-range','ip-wildcard','fqdn','description','tag','disable-override')
        oneOf           = @(,@('ip-netmask','ip-range','ip-wildcard','fqdn'))   # >=1 required; >1 -> warning
        formats         = [ordered]@{ 'ip-netmask'='ip-netmask'; 'ip-range'='ip-range'; 'fqdn'='fqdn' }
        memberlists     = @('tag')
        required        = @()
    }

    'service' = [ordered]@{
        containers      = @('/config/shared/service', "$DEV/service")
        allowedChildren = @('protocol','description','tag')
        required        = @('protocol')
        memberlists     = @('tag')
        nested          = [ordered]@{
            'protocol' = [ordered]@{
                allowedChildren = @('tcp','udp','sctp')
                oneOf           = @(,@('tcp','udp','sctp'))
                nested          = [ordered]@{
                    'tcp' = [ordered]@{ allowedChildren=@('port','source-port','override'); required=@('port'); formats=[ordered]@{ 'port'='port-spec'; 'source-port'='port-spec' } }
                    'udp' = [ordered]@{ allowedChildren=@('port','source-port','override'); required=@('port'); formats=[ordered]@{ 'port'='port-spec'; 'source-port'='port-spec' } }
                    'sctp'= [ordered]@{ allowedChildren=@('port','source-port');            required=@('port'); formats=[ordered]@{ 'port'='port-spec'; 'source-port'='port-spec' } }
                }
            }
        }
    }

    'address-group' = [ordered]@{
        containers      = @('/config/shared/address-group', "$DEV/address-group")
        allowedChildren = @('static','dynamic','description','tag')
        oneOf           = @(,@('static','dynamic'))
        memberlists     = @('static','tag')
        nested          = [ordered]@{ 'dynamic' = [ordered]@{ allowedChildren=@('filter'); required=@('filter') } }
    }

    'security-rule' = [ordered]@{
        containers      = @("$DEV/pre-rulebase/security/rules", "$DEV/post-rulebase/security/rules")
        allowedChildren = @('from','to','source','destination','source-user','application','service','category',
                            'action','description','disabled','log-start','log-end','log-setting','rule-type',
                            'tag','negate-source','negate-destination','profile-setting','hip-profiles','uuid')
        required        = @('from','to','source','destination','application','service','action')
        memberlists     = @('from','to','source','destination','source-user','application','service','category','tag','hip-profiles')
        enums           = [ordered]@{
            'action'    = @('allow','deny','drop','reset-client','reset-server','reset-both')
            'disabled'  = @('yes','no')
            'log-start' = @('yes','no')
            'log-end'   = @('yes','no')
            'rule-type' = @('universal','intrazone','interzone')
            'negate-source'      = @('yes','no')
            'negate-destination' = @('yes','no')
        }
    }

    'device-group' = [ordered]@{
        containers      = @('/config/devices/entry/device-group')
        allowedChildren = @('description','address','address-group','service','service-group','tag',
                            'pre-rulebase','post-rulebase','devices','reference-templates')
        required        = @()
    }

    'template' = [ordered]@{
        containers      = @('/config/devices/entry/template')
        allowedChildren = @('description','config','settings','variable')
        required        = @()
    }

    'template-stack' = [ordered]@{
        containers      = @('/config/devices/entry/template-stack')
        allowedChildren = @('templates','description','devices','settings','variable')
        required        = @('templates','settings')   # 'settings' is commit-required (validate-full)
        memberlists     = @('templates','devices')
    }
}

# Format definitions (documentation; the regexes live in the validator).
$formats = [ordered]@{
    'ip-netmask' = 'IPv4/IPv6, optional /prefix'
    'ip-range'   = 'IP-IP'
    'fqdn'       = 'DNS name'
    'port-spec'  = 'port 1-65535, range a-b or list a,b (no 0 / >65535)'
}

# ---- consistency check against fixtures ----
$fixtureMap = @{
    'shared_address.xml'       = 'address'
    'dg_address.xml'           = 'address'
    'shared_service.xml'       = 'service'
    'shared_address_group.xml' = 'address-group'
    'dg_security_rule.xml'     = 'security-rule'
    'device_group.xml'         = 'device-group'
    'template.xml'             = 'template'
    'template_stack.xml'       = 'template-stack'
}

$warnings = @()
foreach ($f in $fixtureMap.Keys) {
    $path = Join-Path $FixturesDir $f
    if (-not (Test-Path $path)) { $warnings += "missing fixture: $f"; continue }
    [xml]$x = Get-Content -LiteralPath $path -Raw
    $res = $resources[$fixtureMap[$f]]
    foreach ($child in $x.DocumentElement.ChildNodes) {
        if ($child.NodeType -ne 'Element') { continue }
        if ($res.allowedChildren -notcontains $child.Name) {
            $warnings += "[$($fixtureMap[$f])] fixture element '$($child.Name)' is NOT in allowedChildren"
        }
    }
}

$schema = [ordered]@{
    '$comment'      = 'flux Panorama XML-API schema - curated from constraint probing + fixtures. Single source of truth for validate_config.py.'
    target          = 'panorama'
    panosVersion    = $PanosVersion
    api             = 'xml'
    deviceXPathRoot = "/config/devices/entry[@name='localhost.localdomain']"
    note            = "containers are predicate-stripped (no [@name=...]). 'set' enforces enums/format/unknown elements but NOT required/choice - flux checks those itself. choice (oneOf): zero=error, more-than-one=warning (PAN-OS keeps one)."
    formats         = $formats
    resources       = $resources
}

$json = $schema | ConvertTo-Json -Depth 12
Set-Content -LiteralPath $OutFile -Value $json -Encoding UTF8

# versioned archive copy
$verDir = Join-Path (Split-Path $OutFile -Parent) 'versions'
$null = New-Item -ItemType Directory -Force -Path $verDir
$verFile = Join-Path $verDir "panorama-$PanosVersion.json"
Set-Content -LiteralPath $verFile -Value $json -Encoding UTF8

Write-Host "Schema written: $((Resolve-Path $OutFile).Path)  (PAN-OS $PanosVersion)"
Write-Host "Archived:       $((Resolve-Path $verFile).Path)"
Write-Host "Resources:      $($resources.Keys -join ', ')"
if ($warnings.Count) {
    Write-Host "`nConsistency warnings:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else {
    Write-Host "Consistency check OK: all fixture elements are known to the schema."
}
