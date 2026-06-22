# start.ps1 — launch the Contoso Commerce Cloud platform (Windows 11 / PowerShell Core).
#
#   pwsh scripts/start.ps1            # start all services
#   pwsh scripts/start.ps1 -Stop      # stop everything started by this script
#
# Each service runs in its own window. With a .env present (Lab 1+) they export telemetry to
# Azure Monitor; without it they run in DEMO MODE. Open storefront/index.html in a browser
# afterward and point it at http://localhost:5000.
param([switch]$Stop)

$ErrorActionPreference = 'Stop'
# This script lives in scripts/; the platform root is its parent directory.
$root = Split-Path -Parent $PSScriptRoot
$env:PYTHONPATH = $root

# service name -> (script, port)
$services = [ordered]@{
    'payment-service'   = @{ script = 'services/payment_service.py';    port = 5001 }
    'inventory-service' = @{ script = 'services/inventory_service.py';  port = 5002 }
    'order-service'     = @{ script = 'services/order_service.py';      port = 5000 }
    'storefront-ui'     = @{ script = 'services/storefront_service.py'; port = 8080 }
}

$pidFile = Join-Path $root 'state/pids.txt'

if ($Stop) {
    if (Test-Path $pidFile) {
        Get-Content $pidFile | ForEach-Object {
            if ($_ -match '^\d+$') { Stop-Process -Id ([int]$_) -ErrorAction SilentlyContinue }
        }
        Remove-Item $pidFile -ErrorAction SilentlyContinue
        Write-Host "Stopped all platform services." -ForegroundColor Green
    } else {
        Write-Host "No running platform services found." -ForegroundColor Yellow
    }
    return
}

New-Item -ItemType Directory -Force -Path (Join-Path $root 'state') | Out-Null
Remove-Item $pidFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Contoso Commerce Cloud — platform" -ForegroundColor White
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray

foreach ($name in $services.Keys) {
    $svc = $services[$name]
    $env:PORT = "$($svc.port)"
    $proc = Start-Process -FilePath 'python' -ArgumentList $svc.script `
        -WorkingDirectory $root -PassThru
    $proc.Id | Out-File -FilePath $pidFile -Append -Encoding utf8
    Write-Host ("  {0,-18} http://localhost:{1}  (pid {2})" -f $name, $svc.port, $proc.Id) -ForegroundColor Cyan
}
Remove-Item Env:\PORT -ErrorAction SilentlyContinue

# Give the services a moment to bind, then open the storefront web app in the browser.
Start-Sleep -Seconds 3
Start-Process "http://localhost:8080"

Write-Host ""
Write-Host "  Storefront : http://localhost:8080  (opening in your browser)" -ForegroundColor White
Write-Host "  Order API  : http://localhost:5000" -ForegroundColor DarkGray
Write-Host "  Stop all   : pwsh scripts/start.ps1 -Stop" -ForegroundColor DarkGray
Write-Host ""
