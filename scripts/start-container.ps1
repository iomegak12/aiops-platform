# start-container.ps1 — build images and run the platform with Docker Compose.
# PowerShell Core (pwsh) + Docker Desktop (Compose v2: `docker compose`).
#
#   pwsh scripts/start-container.ps1            # build + start (detached)
#   pwsh scripts/start-container.ps1 -Stop      # stop and remove the containers
#   pwsh scripts/start-container.ps1 -Rebuild   # force a no-cache rebuild, then start
param(
    [switch]$Stop,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
# This script lives in scripts/; build context (Dockerfile, compose) is the parent directory.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# ── Preflight ────────────────────────────────────────────────────────────────
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker not found on PATH. Install Docker Desktop: https://www.docker.com/products/docker-desktop/" -ForegroundColor Red
    exit 1
}
docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker Compose v2 not available ('docker compose'). Update Docker Desktop." -ForegroundColor Red
    exit 1
}

if ($Stop) {
    Write-Host "Stopping Contoso Commerce Cloud containers..." -ForegroundColor Yellow
    docker compose down
    return
}

Write-Host ""
Write-Host "  Contoso Commerce Cloud — containers" -ForegroundColor White
Write-Host "  ───────────────────────────────────" -ForegroundColor DarkGray

if ($Rebuild) {
    Write-Host "  Building images (no cache)..." -ForegroundColor Cyan
    docker compose build --no-cache
} else {
    Write-Host "  Building images..." -ForegroundColor Cyan
    docker compose build
}
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed." -ForegroundColor Red; exit 1 }

Write-Host "  Starting containers..." -ForegroundColor Cyan
docker compose up -d
if ($LASTEXITCODE -ne 0) { Write-Host "Startup failed." -ForegroundColor Red; exit 1 }

Start-Sleep -Seconds 3
Start-Process "http://localhost:8080"

Write-Host ""
Write-Host "  Storefront : http://localhost:8080  (opening in your browser)" -ForegroundColor White
Write-Host "  Order API  : http://localhost:5000" -ForegroundColor DarkGray
Write-Host "  Logs       : docker compose logs -f" -ForegroundColor DarkGray
Write-Host "  Stop all   : pwsh scripts/start-container.ps1 -Stop" -ForegroundColor DarkGray
Write-Host ""
