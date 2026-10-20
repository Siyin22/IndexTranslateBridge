#requires -Version 5.1
[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'

function Test-LocalProxy {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        return ($client.ConnectAsync('127.0.0.1', 7897).Wait(400) -and $client.Connected)
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Invoke-UpstreamRequest {
    param([string]$Uri, [bool]$UseProxy)

    Add-Type -AssemblyName System.Net.Http
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $UseProxy
    if ($UseProxy) {
        $handler.Proxy = [System.Net.WebProxy]::new('http://127.0.0.1:7897')
    }
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(25)
    $client.MaxResponseContentBufferSize = 2MB
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('IndexTranslateBridge-Updater/1.0')
    $response = $null
    try {
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            Reason = $response.ReasonPhrase
            Data = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        }
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
    }
}

function Get-UpstreamBytes {
    param([string]$Uri)

    if (Test-LocalProxy) {
        try {
            $response = Invoke-UpstreamRequest -Uri $Uri -UseProxy $true
        } catch {
            Write-Host '代理请求失败，正在尝试直连……'
            $response = Invoke-UpstreamRequest -Uri $Uri -UseProxy $false
        }
    } else {
        $response = Invoke-UpstreamRequest -Uri $Uri -UseProxy $false
    }
    # HTTP errors are not proxy failures.
    if ($response.Status -lt 200 -or $response.Status -ge 300) {
        throw "上游返回 HTTP $($response.Status) $($response.Reason)，请稍后重试。"
    }
    return ,([byte[]]$response.Data)
}

function Write-AtomicBytes {
    param([string]$Path, [byte[]]$Data)

    $temp = Join-Path ([IO.Path]::GetDirectoryName($Path)) ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllBytes($temp, $Data)
        [IO.File]::Replace($temp, $Path, [NullString]::Value)
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Install-UpstreamFiles {
    param([string]$Folder, [byte[]]$ScriptBytes, [byte[]]$NoticeBytes)

    $scriptPath = Join-Path $Folder 'scripts/call_api.py'
    $noticePath = Join-Path $Folder 'THIRD_PARTY_NOTICES.md'
    $oldScript = [IO.File]::ReadAllBytes($scriptPath)
    $oldNotice = [IO.File]::ReadAllBytes($noticePath)
    $backup = Join-Path $Folder ('runtime/update-backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = [IO.Directory]::CreateDirectory($backup)
    [IO.File]::WriteAllBytes((Join-Path $backup 'call_api.py'), $oldScript)
    [IO.File]::WriteAllBytes((Join-Path $backup 'THIRD_PARTY_NOTICES.md'), $oldNotice)

    try {
        Write-AtomicBytes -Path $scriptPath -Data $ScriptBytes
        Write-AtomicBytes -Path $noticePath -Data $NoticeBytes
    } catch {
        $failure = $_.Exception.Message
        try {
            Write-AtomicBytes -Path $scriptPath -Data $oldScript
            Write-AtomicBytes -Path $noticePath -Data $oldNotice
        } catch {
            throw "更新失败，自动恢复也未完成。请从备份恢复两个文件：$backup。错误：$($_.Exception.Message)"
        }
        throw "更新失败，已恢复原文件。备份：$backup。错误：$failure"
    }
    Write-Host "更新完成。原文件备份：$backup"
    Write-Host '如果服务正在运行，请先运行 Stop-IndexTranslate.cmd，再运行 Start-IndexTranslate.cmd 使更新生效。'
}

function Test-UpstreamPython {
    param([byte[]]$Data)

    $python = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pythonArgs = @('-3', '-I')
    if ($null -eq $python) {
        $python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $pythonArgs = @('-I')
    }
    if ($null -eq $python) { throw '找不到 Python。请先安装 Python 3.10 或更新版本。' }
    $temp = [IO.Path]::GetTempFileName()
    # Parse and check the launcher's call without executing downloaded code.
    $check = @'
import ast, inspect, sys
source = open(sys.argv[1], 'rb').read()
compile(source, 'call_api.py', 'exec')
tree = ast.parse(source)
fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'run_proxy_server'), None)
if fn is None:
    raise SystemExit('Missing run_proxy_server')
a = fn.args
params = []
pos = a.posonlyargs + a.args
for i, arg in enumerate(pos):
    kind = inspect.Parameter.POSITIONAL_ONLY if i < len(a.posonlyargs) else inspect.Parameter.POSITIONAL_OR_KEYWORD
    default = None if i >= len(pos) - len(a.defaults) else inspect.Parameter.empty
    params.append(inspect.Parameter(arg.arg, kind, default=default))
if a.vararg:
    params.append(inspect.Parameter(a.vararg.arg, inspect.Parameter.VAR_POSITIONAL))
for arg, default in zip(a.kwonlyargs, a.kw_defaults):
    params.append(inspect.Parameter(arg.arg, inspect.Parameter.KEYWORD_ONLY, default=None if default is not None else inspect.Parameter.empty))
if a.kwarg:
    params.append(inspect.Parameter(a.kwarg.arg, inspect.Parameter.VAR_KEYWORD))
inspect.Signature(params).bind(port=8080, host='127.0.0.1')
'@
    try {
        [IO.File]::WriteAllBytes($temp, $Data)
        & $python.Source @pythonArgs -c $check $temp
        if ($LASTEXITCODE -ne 0) {
            throw '上游脚本语法或 run_proxy_server 参数不兼容，未更新。可能需要先调整 run_bridge.py。'
        }
    } finally {
        [IO.File]::Delete($temp)
    }
}

function Invoke-CallApiUpdate {
    param([string]$Folder, [switch]$CheckOnly)

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $scriptPath = Join-Path $Folder 'scripts/call_api.py'
    $noticePath = Join-Path $Folder 'THIRD_PARTY_NOTICES.md'
    $localBytes = [IO.File]::ReadAllBytes($scriptPath)
    $notice = $utf8.GetString([IO.File]::ReadAllBytes($noticePath))
    $pattern = '- Source revision: \[`(?<sha>[0-9a-f]{40})`\]\(https://github\.com/bilibili/Index-Translate/blob/\k<sha>/inference/llm/call_api\.py\)'
    $revisionMatches = [regex]::Matches($notice, $pattern)
    if ($revisionMatches.Count -ne 1) { throw '无法识别 THIRD_PARTY_NOTICES.md 中的来源提交号，未更改文件。' }
    $current = $revisionMatches[0].Groups['sha'].Value

    Write-Host '正在检查上游 call_api.py……'
    # The public file-history feed avoids GitHub's unauthenticated API quota.
    $history = 'https://github.com/bilibili/Index-Translate/commits/main/inference/llm/call_api.py.atom'
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $textReader = [IO.StringReader]::new($utf8.GetString((Get-UpstreamBytes -Uri $history)))
    $reader = [Xml.XmlReader]::Create($textReader, $settings)
    $feed = [Xml.XmlDocument]::new()
    $feed.XmlResolver = $null
    try { $feed.Load($reader) } finally { $reader.Dispose(); $textReader.Dispose() }
    $entry = $feed.SelectSingleNode("/*[local-name()='feed']/*[local-name()='entry'][1]/*[local-name()='id']")
    if ($null -eq $entry -or $entry.InnerText -notmatch '^tag:github\.com,2008:Grit::Commit/(?<sha>[0-9a-f]{40})$') {
        throw '上游提交信息格式异常，未更改文件。'
    }
    $latest = $Matches['sha']
    $remote = Get-UpstreamBytes -Uri "https://raw.githubusercontent.com/bilibili/Index-Translate/$latest/inference/llm/call_api.py"
    if ($utf8.GetString($localBytes).Replace("`r`n", "`n") -ceq $utf8.GetString($remote).Replace("`r`n", "`n")) {
        Write-Host '本地 call_api.py 与上游最新内容一致，无需更新。'
        return
    }
    Write-Host '发现上游内容与本地不同。'
    Write-Host "本地来源：$current"
    Write-Host "上游提交：$latest"
    Write-Host "查看提交：https://github.com/bilibili/Index-Translate/commit/$latest"
    if ($CheckOnly) { return }
    Write-Host '更新会覆盖本地 call_api.py，并备份脚本和来源记录。'
    $answer = Read-Host '是否更新？输入 Y 确认，直接回车保持现状 [y/N]'
    if ($answer.Trim() -notmatch '^(?i:y|yes)$') {
        Write-Host '已取消更新，保持现状，可继续使用。'
        return
    }
    Test-UpstreamPython -Data $remote
    # Detect edits made while waiting for confirmation.
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($scriptPath)) -cne [Convert]::ToBase64String($localBytes) -or
        $utf8.GetString([IO.File]::ReadAllBytes($noticePath)) -cne $notice) {
        throw '检查期间本地文件已被修改，请重新运行更新检查。'
    }
    $newNotice = $notice.Replace($revisionMatches[0].Value, $revisionMatches[0].Value.Replace($current, $latest))
    Install-UpstreamFiles -Folder $Folder -ScriptBytes $remote -NoticeBytes $utf8.GetBytes($newNotice)
}

# Dot-sourcing only loads functions, allowing isolated offline verification.
if ($MyInvocation.InvocationName -ne '.') {
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        Invoke-CallApiUpdate -Folder (Split-Path $PSScriptRoot -Parent) -CheckOnly:$CheckOnly
    } catch {
        Write-Host "更新检查失败：$($_.Exception.Message)" -ForegroundColor Red
        exit 1
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $tls
    }
}
