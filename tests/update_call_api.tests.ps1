#requires -Version 5.1
# Offline tests. Run with either pwsh or powershell.exe -NoProfile -File ...
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/update_call_api.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-Bytes {
    param([string]$Path, [byte[]]$Expected)
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -ceq [Convert]::ToBase64String($Expected)) "File differs: $Path"
}

# Routing: transport failures retry directly; HTTP errors do not.
$script:routes = @()
function Test-LocalProxy { return $true }
function Invoke-UpstreamRequest {
    param([string]$Uri, [bool]$UseProxy)
    $script:routes += $UseProxy
    if ($UseProxy) { throw 'Simulated proxy connection failure' }
    return [pscustomobject]@{ Status = 200; Reason = 'OK'; Data = [byte[]]@(65) }
}
$data = Get-UpstreamBytes 'https://example.com/test'
Assert-True ($data[0] -eq 65 -and $script:routes.Count -eq 2 -and $script:routes[0] -and -not $script:routes[1]) 'Transport fallback'
$script:routes = @()
function Invoke-UpstreamRequest {
    param([string]$Uri, [bool]$UseProxy)
    $script:routes += $UseProxy
    return [pscustomobject]@{ Status = 403; Reason = 'Forbidden'; Data = [byte[]]@() }
}
$failed = $false
try { $null = Get-UpstreamBytes 'https://example.com/test' } catch { $failed = $true }
Assert-True ($failed -and $script:routes.Count -eq 1) 'HTTP errors must not retry directly'
function Test-LocalProxy { return $false }
function Invoke-UpstreamRequest {
    param([string]$Uri, [bool]$UseProxy)
    Assert-True (-not $UseProxy) 'Unavailable proxy must use direct access'
    return [pscustomobject]@{ Status = 200; Reason = 'OK'; Data = [byte[]]@(65) }
}
$null = Get-UpstreamBytes 'https://example.com/test'

$utf8 = [Text.UTF8Encoding]::new($false)
$script:latest = '1111111111111111111111111111111111111111'
$script:remote = $utf8.GetBytes("def run_proxy_server(port=8080, host='127.0.0.1'):`n    pass`n")
function Get-UpstreamBytes {
    param([string]$Uri)
    if ($Uri.EndsWith('.atom')) {
        return ,$utf8.GetBytes("<feed xmlns='http://www.w3.org/2005/Atom'><entry><id>tag:github.com,2008:Grit::Commit/$script:latest</id></entry></feed>")
    }
    Assert-True ($Uri -ceq "https://raw.githubusercontent.com/bilibili/Index-Translate/$script:latest/inference/llm/call_api.py") 'Download must be pinned to the displayed commit'
    return ,$script:remote
}
function Read-Host { param([string]$Prompt); return $script:answer }
$testFolder = Join-Path ([IO.Path]::GetTempPath()) ('IndexTranslateBridge-tests-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testFolder)
try {
    $null = [IO.Directory]::CreateDirectory((Join-Path $testFolder 'scripts'))
    $scriptPath = Join-Path $testFolder 'scripts/call_api.py'
    $noticePath = Join-Path $testFolder 'THIRD_PARTY_NOTICES.md'
    $oldScript = $utf8.GetBytes("# original local content`r`n")
    $oldNotice = [IO.File]::ReadAllBytes((Join-Path (Split-Path $PSScriptRoot -Parent) 'THIRD_PARTY_NOTICES.md'))
    [IO.File]::WriteAllBytes($scriptPath, $oldScript)
    [IO.File]::WriteAllBytes($noticePath, $oldNotice)

    $script:answer = 'N'
    Invoke-CallApiUpdate -Folder $testFolder
    Assert-Bytes $scriptPath $oldScript
    Assert-Bytes $noticePath $oldNotice
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testFolder 'runtime/update-backups'))) 'Decline must not create backups'

    $script:answer = 'Y'
    Invoke-CallApiUpdate -Folder $testFolder -CheckOnly
    Assert-Bytes $scriptPath $oldScript
    Assert-Bytes $noticePath $oldNotice

    Invoke-CallApiUpdate -Folder $testFolder
    Assert-Bytes $scriptPath $script:remote
    $notice = $utf8.GetString([IO.File]::ReadAllBytes($noticePath))
    Assert-True ($notice.Contains('[`' + $script:latest + '`](https://github.com/bilibili/Index-Translate/blob/' + $script:latest + '/inference/llm/call_api.py)')) 'Both revision hashes must update'
    $backup = @(Get-ChildItem -LiteralPath (Join-Path $testFolder 'runtime/update-backups') -Directory)
    Assert-True ($backup.Count -eq 1) 'One backup directory'
    Assert-Bytes (Join-Path $backup[0].FullName 'call_api.py') $oldScript
    Assert-Bytes (Join-Path $backup[0].FullName 'THIRD_PARTY_NOTICES.md') $oldNotice

    function Read-Host { throw 'No prompt expected for unchanged content' }
    # CRLF versus LF is not an upstream change.
    [IO.File]::WriteAllBytes($scriptPath, $utf8.GetBytes($utf8.GetString($script:remote).Replace("`n", "`r`n")))
    $before = [IO.File]::ReadAllBytes($scriptPath)
    Invoke-CallApiUpdate -Folder $testFolder
    Assert-Bytes $scriptPath $before

    # Reject a new required argument before replacing either local file.
    function Read-Host { param([string]$Prompt); return 'Y' }
    $script:remote = $utf8.GetBytes("def run_proxy_server(required, port=8080, host='127.0.0.1'):`n    pass`n")
    $noticeBefore = [IO.File]::ReadAllBytes($noticePath)
    $failed = $false
    try { Invoke-CallApiUpdate -Folder $testFolder } catch { $failed = $true }
    Assert-True $failed 'Incompatible signature must be rejected'
    Assert-Bytes $scriptPath $before
    Assert-Bytes $noticePath $noticeBefore

    # Simulate failure writing the second file; both originals must be restored.
    $originalWrite = (Get-Item Function:Write-AtomicBytes).ScriptBlock
    $script:failedOnce = $false
    function Write-AtomicBytes {
        param([string]$Path, [byte[]]$Data)
        if ($Path.EndsWith('THIRD_PARTY_NOTICES.md') -and -not $script:failedOnce) {
            $script:failedOnce = $true
            throw 'Simulated write failure'
        }
        & $originalWrite -Path $Path -Data $Data
    }
    $failed = $false
    try { Install-UpstreamFiles -Folder $testFolder -ScriptBytes $oldScript -NoticeBytes $oldNotice } catch { $failed = $true }
    Assert-True ($failed -and $script:failedOnce) 'Injected write failure must be reported'
    Assert-Bytes $scriptPath $before
    Assert-Bytes $noticePath $noticeBefore

    Write-Host "PASS: offline updater tests (PowerShell $($PSVersionTable.PSVersion))"
} finally {
    $resolved = [IO.Path]::GetFullPath($testFolder)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved).StartsWith('IndexTranslateBridge-tests-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
