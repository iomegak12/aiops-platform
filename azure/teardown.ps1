# teardown.ps1 — DELETE the lab resource group and everything in it.
# PowerShell Core (pwsh). DESTRUCTIVE and IRREVERSIBLE. Self-contained.
#
#   pwsh teardown.ps1                 # prompts for typed confirmation
#   pwsh teardown.ps1 -Force          # skip the prompt (use with care)
[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-aiops-lab",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','OK','WARN','ERROR','STEP')][string]$Level='INFO')
    $color = switch ($Level) { 'INFO'{'Cyan'} 'OK'{'Green'} 'WARN'{'Yellow'} 'ERROR'{'Red'} 'STEP'{'White'} }
    $glyph = switch ($Level) { 'INFO'{'•'} 'OK'{'✓'} 'WARN'{'!'} 'ERROR'{'✗'} 'STEP'{'▶'} }
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0} " -f $glyph) -ForegroundColor $color -NoNewline
    Write-Host $Message
}
function Stop-WithError { param([string]$Message) Write-Log $Message -Level ERROR; exit 1 }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Stop-WithError "Azure CLI ('az') not found on PATH."
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "  ║  DESTRUCTIVE: delete the entire lab resource group         ║" -ForegroundColor White
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

$exists = (az group exists -n $ResourceGroup -o tsv) -eq 'true'
if (-not $exists) {
    Write-Log "Resource group '$ResourceGroup' does not exist — nothing to delete." -Level OK
    return
}

Write-Log "This will permanently delete resource group '$ResourceGroup' and ALL resources in it" -Level WARN
Write-Log "(Log Analytics, Application Insights, alert rules, and any data they hold)." -Level WARN

if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "  To confirm, type the resource group name exactly ('$ResourceGroup')"
    if ($confirm -ne $ResourceGroup) {
        Write-Log "Confirmation did not match — aborting. Nothing was deleted." -Level OK
        return
    }
}

Write-Log "Deleting resource group '$ResourceGroup' (running in the background)..." -Level STEP
az group delete -n $ResourceGroup --yes --no-wait
if ($LASTEXITCODE -ne 0) { Stop-WithError "az group delete failed." }
Write-Log "Delete initiated. Azure will remove the group shortly." -Level OK
Write-Host ""
