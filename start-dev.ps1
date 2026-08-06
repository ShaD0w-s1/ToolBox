[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$BackendPort = 8000,

    [ValidateRange(1, 65535)]
    [int]$FrontendPort = 5173,

    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string]$CloudBaseCollectionPrefix = "test_"
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$backendDir = Join-Path $root "ToolBoxBackEnd"
$frontendDir = Join-Path $root "ToolBoxFrontEnd"
$python = Join-Path $backendDir ".venv\Scripts\python.exe"
$npm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "Backend virtual environment not found: $python. Initialize .venv first."
}

if (-not $npm) {
    throw "npm.cmd was not found. Install Node.js and add npm to PATH."
}

if (-not (Test-Path -LiteralPath (Join-Path $frontendDir "node_modules") -PathType Container)) {
    throw "Frontend dependencies are missing. Run npm install in ToolBoxFrontEnd first."
}

$processes = @()

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process -or $Process.HasExited) {
        return
    }

    # Django's reloader and npm can spawn children, so stop the entire process tree.
    & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
}

try {
    Write-Host "Starting backend: http://127.0.0.1:$BackendPort/" -ForegroundColor Cyan
    Write-Host "CloudBase collections: ${CloudBaseCollectionPrefix}work_projects, ${CloudBaseCollectionPrefix}aircraft_templates, ${CloudBaseCollectionPrefix}tool_cart" -ForegroundColor DarkCyan
    $previousCollectionPrefix = $env:CLOUDBASE_COLLECTION_PREFIX
    try {
        $env:CLOUDBASE_COLLECTION_PREFIX = $CloudBaseCollectionPrefix
        $backend = Start-Process `
            -FilePath $python `
            -ArgumentList @("manage.py", "runserver", "127.0.0.1:$BackendPort") `
            -WorkingDirectory $backendDir `
            -NoNewWindow `
            -PassThru
    }
    finally {
        if ($null -eq $previousCollectionPrefix) {
            Remove-Item Env:CLOUDBASE_COLLECTION_PREFIX -ErrorAction SilentlyContinue
        }
        else {
            $env:CLOUDBASE_COLLECTION_PREFIX = $previousCollectionPrefix
        }
    }
    $processes += $backend

    Write-Host "Starting frontend: http://localhost:$FrontendPort/" -ForegroundColor Cyan
    $previousProxyTarget = $env:VITE_DEV_PROXY_TARGET
    try {
        $env:VITE_DEV_PROXY_TARGET = "http://127.0.0.1:$BackendPort"
        $frontend = Start-Process `
            -FilePath $npm.Source `
            -ArgumentList @("run", "dev", "--", "--port", $FrontendPort) `
            -WorkingDirectory $frontendDir `
            -NoNewWindow `
            -PassThru
    }
    finally {
        if ($null -eq $previousProxyTarget) {
            Remove-Item Env:VITE_DEV_PROXY_TARGET -ErrorAction SilentlyContinue
        }
        else {
            $env:VITE_DEV_PROXY_TARGET = $previousProxyTarget
        }
    }
    $processes += $frontend

    Write-Host "Both servers are running. Press Ctrl+C to stop them." -ForegroundColor Green

    while (($processes | Where-Object { -not $_.HasExited }).Count -eq $processes.Count) {
        Start-Sleep -Milliseconds 500
    }

    $stopped = $processes | Where-Object { $_.HasExited } | Select-Object -First 1
    throw "A development server exited unexpectedly (PID $($stopped.Id), exit code $($stopped.ExitCode))."
}
finally {
    Write-Host "Stopping development servers..." -ForegroundColor Yellow
    foreach ($process in $processes) {
        Stop-ProcessTree -Process $process
    }
}
