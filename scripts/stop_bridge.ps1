$ErrorActionPreference = 'Stop'
$bridgePidFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime/bridge.pid'
$bridgeScript = Join-Path $PSScriptRoot 'run_bridge.py'
$bridgeProcess = $null

try {
    if (-not (Test-Path -LiteralPath $bridgePidFile)) {
        Write-Output 'Bridge is already stopped.'
        exit 0
    }

    $bridgePidText = (Get-Content -LiteralPath $bridgePidFile -Raw).Trim()
    $bridgeProcessId = 0
    if (-not [int]::TryParse($bridgePidText, [ref]$bridgeProcessId) -or $bridgeProcessId -le 0) {
        throw 'Invalid bridge.pid. No process was stopped.'
    }

    $bridgeProcess = Get-Process -Id $bridgeProcessId -ErrorAction SilentlyContinue
    if ($null -eq $bridgeProcess) {
        Remove-Item -LiteralPath $bridgePidFile
        Write-Output 'Bridge is already stopped.'
        exit 0
    }

    # Keep a handle to this process while verifying its identity, so PID reuse
    # cannot cause a different process to be stopped.
    $null = $bridgeProcess.Handle
    $bridgeInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $bridgeProcessId"
    $bridgePathPattern = '(?i)(?:^|[\s"])' + [regex]::Escape($bridgeScript) + '(?=[\s"]|$)'
    if ($null -eq $bridgeInfo -or
        $bridgeInfo.Name -notin @('python.exe', 'pythonw.exe') -or
        $bridgeInfo.CommandLine -notmatch $bridgePathPattern) {
        throw 'The saved PID does not belong to this bridge. No process was stopped.'
    }

    if (-not $bridgeProcess.HasExited) {
        $bridgeProcess.Kill()
        if (-not $bridgeProcess.WaitForExit(5000)) {
            throw 'The bridge has not exited yet. Try again shortly.'
        }
    }

    if ((Get-Content -LiteralPath $bridgePidFile -Raw).Trim() -eq $bridgePidText) {
        Remove-Item -LiteralPath $bridgePidFile
    }
    Write-Output 'Bridge stopped. To use translation again, run Start-IndexTranslate.cmd.'
    exit 0
} catch {
    Write-Output ('Unable to stop bridge: ' + $_.Exception.Message)
    exit 1
} finally {
    if ($null -ne $bridgeProcess) {
        $bridgeProcess.Dispose()
    }
}
