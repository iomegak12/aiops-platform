# provision-observability.ps1 — stand up the Azure observability plane for the platform.
# PowerShell Core (pwsh). Self-contained, idempotent, safe to re-run (doubles as re-bootstrap).
#
#   pwsh provision-observability.ps1
#   pwsh provision-observability.ps1 -ResourceGroup my-rg -Location westeurope -Force
#
# What it provisions (each step is announced, checked-before-create, and dependency-verified):
#   1. Azure CLI + login            2. application-insights CLI extension
#   3. Resource group               4. Log Analytics workspace
#   5. Workspace-based App Insights 6. Writes the connection string to ../.env (platform/.env)
#
# Re-running is harmless: existing resources are detected and skipped; .env is refreshed.
#
# Interactive by default: it shows every setting's current value and lets you change it
# (Enter keeps the shown value). Choices are remembered in .provision-state.json next to this
# script, so the next run defaults to what you used last time. Precedence for each setting:
#   explicit -Parameter  >  last run (state file)  >  built-in default.
# Use -NonInteractive (or pass every value as a parameter) to skip the prompts for automation.
[CmdletBinding()]
param(
    [string]$ResourceGroup,
    [string]$Location,
    [string]$WorkspaceName,
    [string]$AppInsightsName,
    [string]$EnvPath = "",   # where to write the connection string; default = platform/.env
    [switch]$NonInteractive, # accept the resolved defaults without prompting (for automation)
    [switch]$Force   # skip the prompt when overwriting an existing, different .env
)

$ErrorActionPreference = 'Stop'

# ── Inlined logger (kept local so this script depends on no other file) ──────
function Write-Log {
    param([string]$Message, [ValidateSet('INFO','OK','WARN','ERROR','STEP')][string]$Level='INFO')
    $color = switch ($Level) { 'INFO'{'Cyan'} 'OK'{'Green'} 'WARN'{'Yellow'} 'ERROR'{'Red'} 'STEP'{'White'} }
    $glyph = switch ($Level) { 'INFO'{'•'} 'OK'{'✓'} 'WARN'{'!'} 'ERROR'{'✗'} 'STEP'{'▶'} }
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0} " -f $glyph) -ForegroundColor $color -NoNewline
    Write-Host $Message
}
function Write-Banner {
    param([string]$Title)
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Blue
    Write-Host ("  ║  {0,-56}║" -f $Title) -ForegroundColor White
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Blue
    Write-Host ""
}
function Stop-WithError { param([string]$Message) Write-Log $Message -Level ERROR; exit 1 }
function Read-Param {
    # Prompt showing the current default; Enter keeps it, any input overrides it.
    param([string]$Label, [string]$Default)
    Write-Host "    $Label " -ForegroundColor Gray -NoNewline
    Write-Host "[$Default]" -ForegroundColor DarkYellow -NoNewline
    $ans = Read-Host " "
    if ([string]::IsNullOrWhiteSpace($ans)) { $Default } else { $ans.Trim() }
}

Write-Banner "Contoso Commerce Cloud · Observability provisioning"

# ── Resolve settings: explicit parameter > last run (state file) > built-in default ──
$stateFile = Join-Path $PSScriptRoot ".provision-state.json"
$state = @{}
if (Test-Path $stateFile) {
    try { $state = Get-Content $stateFile -Raw | ConvertFrom-Json -AsHashtable } catch { $state = @{} }
}
$builtin = @{ ResourceGroup = 'rg-aiops-lab'; Location = 'centralindia'; WorkspaceName = 'law-aiops'; AppInsightsName = 'appi-aiops' }

function Resolve-Setting {
    param([string]$Name, [string]$Value)
    if ($PSBoundParameters_Outer.ContainsKey($Name)) { return $Value }        # explicit -Parameter wins
    if ($state.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$state[$Name])) { return [string]$state[$Name] }
    return $builtin[$Name]                                                     # built-in default
}
$PSBoundParameters_Outer = $PSBoundParameters
$ResourceGroup   = Resolve-Setting 'ResourceGroup'   $ResourceGroup
$Location        = Resolve-Setting 'Location'        $Location
$WorkspaceName   = Resolve-Setting 'WorkspaceName'   $WorkspaceName
$AppInsightsName = Resolve-Setting 'AppInsightsName' $AppInsightsName

if ($state.Count -gt 0) {
    Write-Log "Loaded previous settings from $([System.IO.Path]::GetFileName($stateFile))." -Level INFO
}

# ── Confirm / edit settings (unless -NonInteractive) ─────────────────────────
if (-not $NonInteractive) {
    Write-Host "  Review the configuration — press Enter to keep the shown value, or type a new one:" -ForegroundColor DarkGray
    Write-Host ""
    $ResourceGroup   = Read-Param 'Resource group   ' $ResourceGroup
    $Location        = Read-Param 'Azure location   ' $Location
    $WorkspaceName   = Read-Param 'Log Analytics    ' $WorkspaceName
    $AppInsightsName = Read-Param 'App Insights name' $AppInsightsName
    Write-Host ""
}

# ── Remember these choices for next time ─────────────────────────────────────
@{ ResourceGroup = $ResourceGroup; Location = $Location; WorkspaceName = $WorkspaceName; AppInsightsName = $AppInsightsName } |
    ConvertTo-Json | Out-File -FilePath $stateFile -Encoding utf8

Write-Log "Target : RG '$ResourceGroup' / Location '$Location'" -Level INFO
Write-Log "Plan   : Log Analytics '$WorkspaceName' + App Insights '$AppInsightsName' (workspace-based)" -Level INFO

# ── 1. Azure CLI + login ─────────────────────────────────────────────────────
Write-Log "Step 1/6 — checking Azure CLI and sign-in..." -Level STEP
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Stop-WithError "Azure CLI ('az') not found on PATH. Install it: https://aka.ms/azcli"
}
$acct = az account show -o json 2>$null | ConvertFrom-Json
if (-not $acct) {
    Write-Log "You are not signed in to Azure." -Level WARN
    Write-Log "Sign in first, then re-run this script:  az login" -Level WARN
    Stop-WithError "Aborting — Azure sign-in required (run 'az login' explicitly)."
}
Write-Log "Signed in to subscription: $($acct.name) ($($acct.id))" -Level OK

# ── 2. application-insights extension ────────────────────────────────────────
Write-Log "Step 2/6 — ensuring the 'application-insights' CLI extension (needed for app-insights commands)..." -Level STEP
$hasExt = az extension show -n application-insights -o tsv --query name 2>$null
if ([string]::IsNullOrWhiteSpace($hasExt)) {
    Write-Log "Installing 'application-insights' extension..." -Level INFO
    az extension add -n application-insights -o none
    Write-Log "Extension installed." -Level OK
} else {
    Write-Log "Extension already installed — skipping." -Level OK
}

# ── 3. Resource group ────────────────────────────────────────────────────────
Write-Log "Step 3/6 — resource group '$ResourceGroup' (the container for all lab resources)..." -Level STEP
$rgExists = (az group exists -n $ResourceGroup -o tsv) -eq 'true'
if ($rgExists) {
    Write-Log "Resource group already exists — skipping creation." -Level OK
} else {
    Write-Log "Creating resource group '$ResourceGroup' in '$Location'..." -Level INFO
    az group create -n $ResourceGroup -l $Location -o none
    if ($LASTEXITCODE -ne 0) { Stop-WithError "Failed to create resource group." }
    Write-Log "Resource group created." -Level OK
}

# ── 4. Log Analytics workspace ───────────────────────────────────────────────
Write-Log "Step 4/6 — Log Analytics workspace '$WorkspaceName' (where all telemetry is stored)..." -Level STEP
$workspaceId = az monitor log-analytics workspace show -g $ResourceGroup -n $WorkspaceName --query id -o tsv 2>$null
if (-not [string]::IsNullOrWhiteSpace($workspaceId)) {
    Write-Log "Workspace already exists — skipping creation." -Level OK
} else {
    Write-Log "Creating workspace '$WorkspaceName'..." -Level INFO
    az monitor log-analytics workspace create -g $ResourceGroup -n $WorkspaceName -l $Location -o none
    if ($LASTEXITCODE -ne 0) { Stop-WithError "Failed to create Log Analytics workspace." }
    $workspaceId = az monitor log-analytics workspace show -g $ResourceGroup -n $WorkspaceName --query id -o tsv
    Write-Log "Workspace created." -Level OK
}
# The customerId GUID — what azure-monitor-query needs to read this workspace (used by L4's notebook).
$workspaceGuid = az monitor log-analytics workspace show -g $ResourceGroup -n $WorkspaceName --query customerId -o tsv 2>$null

# ── 5. Workspace-based App Insights (depends on RG + workspace) ───────────────
Write-Log "Step 5/6 — Application Insights '$AppInsightsName' (workspace-based; the app's telemetry endpoint)..." -Level STEP
if ([string]::IsNullOrWhiteSpace($workspaceId)) {
    Stop-WithError "Dependency missing: Log Analytics workspace id not resolved. Re-run; if it persists, check the workspace."
}
$conn = az monitor app-insights component show --app $AppInsightsName -g $ResourceGroup --query connectionString -o tsv 2>$null
if (-not [string]::IsNullOrWhiteSpace($conn)) {
    Write-Log "App Insights already exists — skipping creation." -Level OK
} else {
    Write-Log "Creating App Insights '$AppInsightsName' linked to the workspace..." -Level INFO
    az monitor app-insights component create --app $AppInsightsName -g $ResourceGroup -l $Location `
        --workspace $workspaceId --application-type web -o none
    if ($LASTEXITCODE -ne 0) { Stop-WithError "Failed to create App Insights component." }
    $conn = az monitor app-insights component show --app $AppInsightsName -g $ResourceGroup --query connectionString -o tsv
    Write-Log "App Insights created." -Level OK
}
if ([string]::IsNullOrWhiteSpace($conn)) { Stop-WithError "Could not read the App Insights connection string." }

# ── 6. Write platform/.env (path derived from this script's location) ─────────
# Merge, don't clobber: this script OWNS the two Azure-derived keys below, but it must
# PRESERVE any other keys the user added by hand (e.g. the EMBED_* Foundry settings that
# L4's clustering notebook reads). A naive full overwrite would wipe them on every
# re-bootstrap. So we read the existing file into a key→value map, overwrite only our
# managed keys, seed empty embedding placeholders if absent, and write the merged result.
Write-Log "Step 6/6 — writing connection string + workspace id to platform/.env (preserving your other keys)..." -Level STEP
$envPath = if ([string]::IsNullOrWhiteSpace($EnvPath)) {
    Join-Path (Split-Path $PSScriptRoot -Parent) ".env"          # default: platform/.env (parent of azure/)
} else { $EnvPath }

# Ordered map so the file reads predictably; case-sensitive keys (env-var convention).
$envMap = [ordered]@{}
if (Test-Path $envPath) {
    foreach ($line in (Get-Content $envPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*#') { continue }                    # keep it simple: drop comment lines
        $kv = $line -split '=', 2
        if ($kv.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($kv[0])) { $envMap[$kv[0].Trim()] = $kv[1] }
    }
}

# Our managed keys (always refreshed from Azure):
$envMap['APPLICATIONINSIGHTS_CONNECTION_STRING'] = $conn
if (-not [string]::IsNullOrWhiteSpace($workspaceGuid)) { $envMap['LAW_WORKSPACE_ID'] = $workspaceGuid }

# Embedding placeholders for L4 — seed only if the user hasn't set them, so we never overwrite real values:
foreach ($k in 'EMBED_ENDPOINT','EMBED_KEY','EMBED_DEPLOY') {
    if (-not $envMap.Contains($k)) { $envMap[$k] = '' }
}

$newBody = ($envMap.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
$writeIt = $true
if (Test-Path $envPath) {
    $existing = (Get-Content $envPath -Raw -ErrorAction SilentlyContinue)
    if ($existing -and $existing.Trim() -eq $newBody.Trim()) {
        Write-Log ".env already up to date — no change." -Level OK
        $writeIt = $false
    } elseif (-not $Force) {
        Write-Host ""
        $ans = Read-Host "  An existing .env differs (managed keys will be refreshed, your other keys kept). Update it? [Y/n]"
        if ($ans -match '^(n|no)$') { Write-Log "Left existing .env untouched (use -Force to update)." -Level WARN; $writeIt = $false }
    }
}
if ($writeIt) {
    $newBody | Out-File -FilePath $envPath -Encoding utf8
    Write-Log ".env written: $envPath" -Level OK
    if ([string]::IsNullOrWhiteSpace($envMap['EMBED_ENDPOINT'])) {
        Write-Log "Note: EMBED_ENDPOINT / EMBED_KEY / EMBED_DEPLOY are blank — fill them in before running L4 (Foundry embedding deployment)." -Level WARN
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
$mask = if ($conn.Length -gt 24) { $conn.Substring(0,24) + "…(masked)" } else { "(set)" }
Write-Host ""
Write-Host "  ── Summary ─────────────────────────────────" -ForegroundColor White
Write-Log "Resource group : $ResourceGroup" -Level INFO
Write-Log "Workspace      : $WorkspaceName" -Level INFO
Write-Log "App Insights   : $AppInsightsName" -Level INFO
Write-Log "Connection str : $mask" -Level INFO
Write-Log ".env path      : $envPath" -Level INFO
Write-Log "Settings saved : $stateFile (reused as defaults next run)" -Level INFO
Write-Host ""
Write-Log "Observability plane ready. Start the platform: pwsh ..\scripts\start.ps1" -Level OK
Write-Host ""
