# load.ps1 — headless traffic generator for the platform (drives the order service).
# PowerShell Core (pwsh). Use this for a pre-class warm-up or a quick burst; for organic,
# human-driven traffic use the storefront's "Auto-shop" button instead.
#   pwsh scripts/load.ps1                 # ~200 checkouts, ~10% baseline failures
#   pwsh scripts/load.ps1 -Count 500
#   pwsh scripts/load.ps1 -Url http://localhost:5000/order -DelayMs 50
param(
    [int]$Count = 200,
    [string]$Url = "http://localhost:5000/order",
    [int]$DelayMs = 10,
    [int]$TimeoutSec = 5,
    [int]$MinBatch = 5,
    [int]$MaxBatch = 10
)

# ── Helpers ─────────────────────────────────────────────────────────────────
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'INFO'  { 'Cyan' }
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
    }
    $stamp = (Get-Date).ToString('HH:mm:ss')
    Write-Host "[$stamp] " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-5}" -f $Level) -ForegroundColor $color -NoNewline
    Write-Host " $Message"
}

# ── Run ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Contoso Commerce Cloud — Load Generator" -ForegroundColor White
Write-Host "  ───────────────────────────────────────" -ForegroundColor DarkGray
Write-Log "Target    : $Url"      -Level INFO
Write-Log "Requests  : $Count"    -Level INFO
Write-Log "Batch     : $MinBatch-$MaxBatch concurrent (random)" -Level INFO
Write-Log "Delay     : ${DelayMs}ms / Timeout: ${TimeoutSec}s" -Level INFO
Write-Host ""

# The /order endpoint expects a JSON body (OrderRequest); send one or FastAPI returns 422.
$body = '{"sku":"SKU-001","amount_usd":49.99}'

$sw        = [System.Diagnostics.Stopwatch]::StartNew()
$success   = 0
$failed    = 0
$latencies = [System.Collections.Generic.List[double]]::new()
$errors    = @{}
$sent      = 0

while ($sent -lt $Count) {
    $batch = Get-Random -Minimum $MinBatch -Maximum ($MaxBatch + 1)
    $batch = [math]::Min($batch, $Count - $sent)

    $results = 1..$batch | ForEach-Object -ThrottleLimit $batch -Parallel {
        $reqSw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            Invoke-RestMethod -Uri $using:Url -Method Post -Body $using:body -ContentType 'application/json' -TimeoutSec $using:TimeoutSec | Out-Null
            $reqSw.Stop()
            [pscustomobject]@{ Ok = $true; Latency = $reqSw.Elapsed.TotalMilliseconds; Reason = $null }
        }
        catch {
            $reqSw.Stop()
            $reason = $_.Exception.Message
            if ($_.Exception.Response) { $reason = "HTTP $([int]$_.Exception.Response.StatusCode)" }
            [pscustomobject]@{ Ok = $false; Latency = $reqSw.Elapsed.TotalMilliseconds; Reason = $reason }
        }
    }

    foreach ($r in $results) {
        if ($r.Ok) { $success++; $latencies.Add($r.Latency) }
        else {
            $failed++
            if ($errors.ContainsKey($r.Reason)) { $errors[$r.Reason]++ } else { $errors[$r.Reason] = 1 }
        }
    }
    $sent += $batch

    $done = $success + $failed
    $pct  = [math]::Round(($done / $Count) * 100)
    $rate = if ($done) { [math]::Round(($success / $done) * 100, 1) } else { 0 }
    Write-Progress -Activity "Sending checkouts to $Url (batch x$batch)" `
        -Status "$done/$Count  •  OK $success  •  FAIL $failed  •  success ${rate}%" `
        -PercentComplete $pct

    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

$sw.Stop()
Write-Progress -Activity "Sending checkouts" -Completed

# ── Summary ─────────────────────────────────────────────────────────────────
$elapsed     = $sw.Elapsed
$successRate = if ($Count) { [math]::Round(($success / $Count) * 100, 1) } else { 0 }
$throughput  = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($Count / $elapsed.TotalSeconds, 1) } else { 0 }

$avg = $p95 = $min = $max = 0
if ($latencies.Count -gt 0) {
    $sorted = $latencies | Sort-Object
    $avg = [math]::Round(($latencies | Measure-Object -Average).Average, 1)
    $min = [math]::Round($sorted[0], 1)
    $max = [math]::Round($sorted[-1], 1)
    $p95 = [math]::Round($sorted[[math]::Min($sorted.Count - 1, [int][math]::Ceiling($sorted.Count * 0.95) - 1)], 1)
}

Write-Host ""
Write-Host "  ── Summary ─────────────────────────────────" -ForegroundColor White
Write-Log "Total checkouts : $Count"                   -Level INFO
Write-Log "Succeeded       : $success"                  -Level OK
Write-Log "Failed          : $failed"                   -Level $(if ($failed) { 'ERROR' } else { 'OK' })
Write-Log "Success rate    : ${successRate}%"           -Level $(if ($successRate -ge 90) { 'OK' } elseif ($successRate -ge 50) { 'WARN' } else { 'ERROR' })
Write-Log "Elapsed         : $([math]::Round($elapsed.TotalSeconds, 1))s ($throughput req/s)" -Level INFO
if ($latencies.Count -gt 0) {
    Write-Log "Latency (ms)    : avg $avg • min $min • p95 $p95 • max $max" -Level INFO
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Log "Error breakdown:" -Level WARN
    $errors.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
        Write-Host ("           {0,4}x  {1}" -f $_.Value, $_.Key) -ForegroundColor Red
    }
}
Write-Host ""
