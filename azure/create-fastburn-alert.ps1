# create-fastburn-alert.ps1 — create/update the OrderService fast-burn SLO alert.
# PowerShell Core (pwsh). Requires: az CLI + 'scheduled-query' extension. Self-contained.
#
#   Usage:
#     pwsh create-fastburn-alert.ps1 -ResourceGroup rg-aiops-lab -AppInsightsName appi-aiops
#     pwsh create-fastburn-alert.ps1 -ResourceGroup rg-aiops-lab -AppInsightsId /subscriptions/.../components/appi-aiops
#
# Lab 2 config: 99% SLO -> 1% error budget. Fast burn = >14.4x budget burn over 5 min,
# which is an error rate > 14.4% (0.144) in the window. Fires Sev1 when the query returns
# any row. NOTE: the app's baseline ~10% failure sits BELOW this threshold by design — a
# steady-but-bad service does not page; you must concentrate failures (hammer it) to trip it.
# That is the lab's point: page on acceleration, not on badness.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    # Provide EITHER the App Insights name (resolved via az) OR the full resource ID.
    [string]$AppInsightsName,
    [string]$AppInsightsId,

    [string]$AlertName        = "OrderService-FastBurn",
    [double]$ErrorRateThreshold = 0.144,   # 14.4x burn of a 1% (99% SLO) budget
    [string]$EvaluationFrequency = "5m",
    [string]$WindowSize         = "5m",
    [int]$Severity              = 1
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $color = switch ($Level) { 'INFO' { 'Cyan' } 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } }
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-5}" -f $Level) -ForegroundColor $color -NoNewline
    Write-Host " $Message"
}

function Stop-WithError {
    param([string]$Message)
    Write-Log $Message -Level ERROR
    exit 1
}

# ── Preflight ────────────────────────────────────────────────────────────────
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Stop-WithError "Azure CLI ('az') not found on PATH. Install it: https://aka.ms/azcli"
}

# Ensure the scheduled-query extension (this script's own dependency).
$hasExt = az extension show -n scheduled-query -o tsv --query name 2>$null
if ([string]::IsNullOrWhiteSpace($hasExt)) {
    Write-Log "Installing 'scheduled-query' extension..." -Level INFO
    az extension add -n scheduled-query -o none
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    Stop-WithError "ResourceGroup is empty."
}

# Resolve the App Insights resource ID if only a name was given.
if ([string]::IsNullOrWhiteSpace($AppInsightsId)) {
    if ([string]::IsNullOrWhiteSpace($AppInsightsName)) {
        Stop-WithError "Provide either -AppInsightsId or -AppInsightsName."
    }
    Write-Log "Resolving App Insights ID for '$AppInsightsName' in '$ResourceGroup'..."
    $AppInsightsId = az monitor app-insights component show `
        -g $ResourceGroup -a $AppInsightsName --query id -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($AppInsightsId)) {
        Stop-WithError "Could not resolve App Insights '$AppInsightsName'. Check the name, RG, and 'az login'."
    }
}

# ── Build the KQL (must end in a tabular statement) ──────────────────────────
$kql = @"
requests
| where timestamp > ago($WindowSize)
| summarize total = count(), errors = countif(success == false)
| extend errorRate = todouble(errors) / todouble(total)
| where total > 0 and errorRate > $ErrorRateThreshold
"@

if ([string]::IsNullOrWhiteSpace($kql)) {
    Stop-WithError "KQL query is empty — aborting before calling az."
}

# ── Summary before the call ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  Fast-Burn Alert (99% SLO / 1% budget)" -ForegroundColor White
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
Write-Log "Resource group : $ResourceGroup"
Write-Log "Scope (AppI)   : $AppInsightsId"
Write-Log "Alert name     : $AlertName"
Write-Log "Threshold      : errorRate > $ErrorRateThreshold over $WindowSize (= 14.4x burn)"
Write-Log "Frequency      : eval $EvaluationFrequency / window $WindowSize / sev $Severity"
Write-Log "KQL length     : $($kql.Length) chars"
Write-Host ""

# ── Create (idempotent: az updates if the rule already exists) ───────────────
Write-Log "Creating/updating scheduled-query rule..." -Level INFO
az monitor scheduled-query create `
    -g $ResourceGroup -n $AlertName `
    --scopes $AppInsightsId `
    --condition "count 'rows' > 0" `
    --condition-query rows=$kql `
    --evaluation-frequency $EvaluationFrequency --window-size $WindowSize `
    --severity $Severity `
    --description "Fast burn: >14.4x error budget burn over $WindowSize (99% SLO)"

if ($LASTEXITCODE -ne 0) {
    Stop-WithError "az command failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Log "Alert '$AlertName' created/updated successfully." -Level OK
Write-Host ""
