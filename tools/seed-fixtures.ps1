<#
.SYNOPSIS
    flux - seeds representative Panorama objects and captures real XML fixtures.

.DESCRIPTION
    For each supported resource type, creates a sample object via the XML-API `set`,
    reads it back via `get`, and stores the XML the system wrote back (incl. defaults)
    as a fixture under schema/fixtures/. These fixtures are the basis for the schema
    compiler.

    Also writes schema/source-info.json (PAN-OS version / model / hostname of the live
    box) so the compiled schema can be bound to that PAN-OS version.

    Order respects references (address before address-group, template before stack).
    With -Cleanup the seeded objects are deleted afterwards (candidate config; NO commit
    is performed, so no change to managed devices).

.EXAMPLE
    $env:PAN_HOST='192.168.99.2'; $env:PAN_USER='admin'; $env:PAN_PASSWORD='***'
    .\tools\seed-fixtures.ps1 -Cleanup
#>
[CmdletBinding()]
param(
    [string]$PanHost  = $env:PAN_HOST,
    [string]$User     = $env:PAN_USER,
    [string]$Password = $env:PAN_PASSWORD,
    [string]$OutDir,
    [switch]$Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty in the param() default under -File; resolve in the body.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
if (-not $OutDir) { $OutDir = Join-Path $here '..\schema\fixtures' }
. (Join-Path $here 'pan-api.ps1')

$null = Connect-Pan -PanHost $PanHost -User $User -Password $Password
$OutDir = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path $OutDir)).Path
$DEV = "/config/devices/entry[@name='localhost.localdomain']"

# Record the live source so the schema can be bound to this PAN-OS version.
$sys = (Invoke-PanOp '<show><system><info></info></system></show>').response.result.system
$srcInfo = [ordered]@{
    panosVersion = [string]$sys.'sw-version'
    model        = [string]$sys.model
    hostname     = [string]$sys.hostname
}
$srcPath = Join-Path (Split-Path $OutDir -Parent) 'source-info.json'
Set-Content -LiteralPath $srcPath -Value ($srcInfo | ConvertTo-Json) -Encoding UTF8

# Representative seeds. 'element' = inner XML body of the node at xpath.
$seeds = @(
    @{ key='shared-address';        file='shared_address.xml';
       xpath="/config/shared/address/entry[@name='flux-web-srv']";
       element='<ip-netmask>10.10.10.10/32</ip-netmask><description>flux seed address</description>' }

    @{ key='shared-service';        file='shared_service.xml';
       xpath="/config/shared/service/entry[@name='flux-tcp-8080']";
       element='<protocol><tcp><port>8080</port></tcp></protocol><description>flux seed service</description>' }

    @{ key='shared-address-group';  file='shared_address_group.xml';
       xpath="/config/shared/address-group/entry[@name='flux-web-grp']";
       element='<static><member>flux-web-srv</member></static>' }

    @{ key='device-group';          file='device_group.xml';
       xpath="$DEV/device-group/entry[@name='flux-dg']";
       element='<description>flux demo device group</description>' }

    @{ key='dg-address';            file='dg_address.xml';
       xpath="$DEV/device-group/entry[@name='flux-dg']/address/entry[@name='flux-db-srv']";
       element='<ip-netmask>10.20.20.20/32</ip-netmask>' }

    @{ key='dg-security-rule';      file='dg_security_rule.xml';
       xpath="$DEV/device-group/entry[@name='flux-dg']/pre-rulebase/security/rules/entry[@name='flux-allow-web']";
       element='<from><member>any</member></from><to><member>any</member></to><source><member>any</member></source><destination><member>flux-web-srv</member></destination><source-user><member>any</member></source-user><application><member>web-browsing</member></application><service><member>application-default</member></service><action>allow</action>' }

    @{ key='template';              file='template.xml';
       xpath="$DEV/template/entry[@name='flux-tpl']";
       element='<description>flux demo template</description>' }

    @{ key='template-stack';        file='template_stack.xml';
       xpath="$DEV/template-stack/entry[@name='flux-stack']";
       element='<templates><member>flux-tpl</member></templates><settings></settings><description>flux demo stack</description>' }
)

# PAN-OS adds bookkeeping attributes to candidate-config nodes that are NOT part of
# the schema. Remove them recursively -> clean canonical XML.
$script:MetaAttrs = @('admin','dirtyId','time','uuid','loc')
function Remove-PanMeta([System.Xml.XmlNode]$Node) {
    if ($Node.Attributes) {
        foreach ($a in $script:MetaAttrs) { $null = $Node.Attributes.RemoveNamedItem($a) }
    }
    foreach ($child in $Node.ChildNodes) { Remove-PanMeta $child }
}

function Format-Xml([xml]$Xml) {
    Remove-PanMeta $Xml.DocumentElement
    $sw = New-Object System.IO.StringWriter
    $xw = New-Object System.Xml.XmlTextWriter($sw)
    $xw.Formatting = [System.Xml.Formatting]::Indented
    $xw.Indentation = 2
    $Xml.WriteContentTo($xw); $xw.Flush()
    $sw.ToString()
}

$results = foreach ($s in $seeds) {
    $setResp = Invoke-PanConfig -Action set -XPath $s.xpath -Element $s.element
    $setOk = Test-PanSuccess $setResp
    $getOk = $false; $err = $null
    if ($setOk) {
        $getResp = Invoke-PanConfig -Action get -XPath $s.xpath
        $getOk = Test-PanSuccess $getResp
        if ($getOk -and $getResp.response.result) {
            $getXml = Format-Xml ([xml]$getResp.response.result.InnerXml)
            Set-Content -LiteralPath (Join-Path $OutDir $s.file) -Value $getXml -Encoding UTF8
        }
    } else { $err = Get-PanError $setResp }
    [pscustomobject]@{ Key=$s.key; Set=$setOk; Get=$getOk; File=$s.file; Error=$err }
}

Write-Host "Source: PAN-OS $($srcInfo.panosVersion) ($($srcInfo.model), $($srcInfo.hostname)) -> $srcPath"
$results | Format-Table -AutoSize | Out-String | Write-Host

if ($Cleanup) {
    Write-Host "`n--- cleanup (delete in reverse order) ---"
    [array]::Reverse($seeds)
    foreach ($s in $seeds) {
        $d = Invoke-PanConfig -Action delete -XPath $s.xpath
        Write-Host ("delete {0,-22} -> {1}" -f $s.key, $d.response.status)
    }
}
