$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $PSScriptRoot
$launchScript = Join-Path $PSScriptRoot 'launch.py'
$runtimeDir = Join-Path $projectDir 'runtime'
$errorLog = Join-Path $runtimeDir 'autostart.log'

try {
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pythonLauncher) {
        & $pythonLauncher.Source -3 -I $launchScript
    } else {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) {
            throw 'Python 3 was not found. Install Python and enable Python Launcher or add python.exe to PATH.'
        }
        & $python.Source -I $launchScript
    }
    exit $LASTEXITCODE
} catch {
    "$(Get-Date -Format s) $($_.Exception.Message)" | Add-Content -LiteralPath $errorLog -Encoding UTF8
    exit 1
}
