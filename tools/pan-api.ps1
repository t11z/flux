<#
.SYNOPSIS
    flux - Panorama XML-API wrapper (PowerShell + curl.exe).

.DESCRIPTION
    A thin wrapper around the PAN-OS/Panorama *XML-API* (XPath based). Deliberately
    XML-API only - that is the interface the panos Terraform modules (pango SDK) speak.
    NO REST API here.

    Auth: call Connect-Pan / Get-PanKey once (keygen from user+password) -> afterwards
    only the API key is used. The key lives in process memory only ($script:PanKey);
    the password is NEVER persisted.

    Usage:
        . .\tools\pan-api.ps1
        Connect-Pan -PanHost 192.168.99.2 -User admin -Password '****'
        (Invoke-PanOp '<show><system><info></info></system></show>').response.result.system.'sw-version'
        Invoke-PanConfig -Action get -XPath "/config/shared/address"

    Credentials may also come from environment variables:
        $env:PAN_HOST, $env:PAN_USER, $env:PAN_PASSWORD, $env:PAN_KEY

.NOTES
    Self-signed cert -> curl.exe -k. curl returns a string array in PS, hence -join "`n"
    everywhere. Parameters with special chars (password, XML cmd bodies) go via
    --data-urlencode.
#>

Set-StrictMode -Version Latest

$script:PanHost = $env:PAN_HOST
$script:PanKey  = $env:PAN_KEY

function Set-PanHost {
    param([Parameter(Mandatory)][string]$PanHost)
    $script:PanHost = $PanHost
}

function Get-PanHost { $script:PanHost }

function Get-PanKey {
    <# Returns the cached key; generates it via keygen if needed (or -Force). #>
    [CmdletBinding()]
    param(
        [string]$PanHost  = $script:PanHost,
        [string]$User     = $env:PAN_USER,
        [string]$Password = $env:PAN_PASSWORD,
        [switch]$Force
    )
    if ($script:PanKey -and -not $Force) { return $script:PanKey }
    if (-not $PanHost)  { throw "PanHost missing (-PanHost or `$env:PAN_HOST)." }
    if (-not $User -or -not $Password) { throw "User/password required for keygen (-User/-Password or `$env:PAN_USER/PAN_PASSWORD)." }

    $resp = (& curl.exe -k -s "https://$PanHost/api/" `
                --data-urlencode "type=keygen" `
                --data-urlencode "user=$User" `
                --data-urlencode "password=$Password") -join "`n"

    if ($resp -match '<key>(.*?)</key>') {
        $script:PanHost = $PanHost
        $script:PanKey  = $matches[1]
        return $script:PanKey
    }
    throw "keygen failed: $resp"
}

function Connect-Pan {
    <# Convenience entry point: set host + fetch key. The password is not returned/stored. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PanHost,
        [string]$User     = $env:PAN_USER,
        [string]$Password = $env:PAN_PASSWORD
    )
    $null = Get-PanKey -PanHost $PanHost -User $User -Password $Password -Force
    [pscustomobject]@{ PanHost = $script:PanHost; Connected = [bool]$script:PanKey }
}

function Invoke-PanApi {
    <# Low level: takes a param hashtable, appends the key, returns [xml]. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Params,
        [string]$PanHost = $script:PanHost,
        [string]$Key     = $script:PanKey
    )
    if (-not $PanHost) { throw "PanHost missing. Call Connect-Pan first." }
    if (-not $Key)     { throw "No API key. Call Connect-Pan / Get-PanKey first." }

    # XML-bearing values (element/cmd) contain double-quoted attributes; Windows
    # PowerShell mangles embedded quotes when passing args to curl.exe. Route any
    # markup value through a temp file (curl's name@file form URL-encodes the file
    # content) so the quoting never crosses the native-process boundary.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $tmpFiles  = @()
    $curlArgs  = @('-k','-s',"https://$PanHost/api/")
    foreach ($k in $Params.Keys) {
        $val = [string]$Params[$k]
        if ($val -match '[<>"&]') {
            $tmp = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText($tmp, $val, $utf8NoBom)
            $tmpFiles += $tmp
            $curlArgs += @('--data-urlencode', "$k@$tmp")
        } else {
            $curlArgs += @('--data-urlencode', "$k=$val")
        }
    }
    $curlArgs += @('--data-urlencode', "key=$Key")

    try {
        $raw = (& curl.exe @curlArgs) -join "`n"
    } finally {
        foreach ($f in $tmpFiles) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    try { return [xml]$raw }
    catch { throw "response is not XML (check auth/endpoint). Start: $($raw.Substring(0,[Math]::Min(200,$raw.Length)))" }
}

function Invoke-PanConfig {
    <# type=config with XPath. -Element only for set/edit; -NewName only for rename. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('get','show','set','edit','delete','rename','move','clone')][string]$Action,
        [Parameter(Mandatory)][string]$XPath,
        [string]$Element,
        [string]$NewName
    )
    $p = @{ type = 'config'; action = $Action; xpath = $XPath }
    if ($PSBoundParameters.ContainsKey('Element')) { $p['element'] = $Element }
    if ($NewName) { $p['newname'] = $NewName }
    Invoke-PanApi -Params $p
}

function Invoke-PanOp {
    <# type=op; -Cmd is the XML-wrapped command, e.g. '<show><system><info></info></system></show>'. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Cmd)
    Invoke-PanApi -Params @{ type = 'op'; cmd = $Cmd }
}

function Test-PanSuccess {
    <# True on <response status="success">. #>
    param([Parameter(Mandatory)][xml]$Response)
    $Response.response.status -eq 'success'
}

function Get-PanError {
    <# Extracts error text from a response. PAN-OS nests errors as
       <msg><line><line><![CDATA[...]]></line>...</line></msg>. We collect the leaf
       <line> nodes; falls back to the msg text otherwise. #>
    param([Parameter(Mandatory)][xml]$Response)
    $leaves = $Response.SelectNodes('//msg//line[not(line)]')
    if ($leaves -and $leaves.Count -gt 0) {
        return (($leaves | ForEach-Object { $_.InnerText.Trim() }) -join ' | ')
    }
    $msgNode = $Response.SelectSingleNode('//msg')
    if ($msgNode) { return $msgNode.InnerText.Trim() }
    return $null
}
