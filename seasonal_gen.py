#!/usr/bin/env python
"""
seasonal_gen.py - emit a short, synthetic *seasonal* business metric for Contoso Commerce Cloud.

The metric is **checkout volume** (checkouts per minute) for the order-service. In the real
world it rises and falls on a daily cycle: busy in the day, quiet overnight. A 24-hour cycle
can't be watched inside a 70-minute lab, so this emits a *compressed* season — a sine wave with
a SHORT period (default 120 s) plus noise, sampled every ~10 s for a few minutes.

    checkouts_per_min = base + amplitude * sin(2*pi*t/period) + noise   (+ injected surge/collapse)

Two off-pattern events are injected so the lab's anomaly queries have something real to catch:
  - a sudden COLLAPSE during a quiet window (volume craters, but stays under a naive "too-high"
    alarm of 90 — so a static threshold that only looks UP misses it entirely), and
  - a sudden SURGE that briefly overshoots the seasonal peak (e.g. a bot / retry storm).

Self-contained: needs only APPLICATIONINSIGHTS_CONNECTION_STRING (in platform/.env, written by
the provisioning script). No Data Collection Rule, custom table, or extra Azure setup. Each
sample is emitted as one OpenTelemetry log record via the same azure-monitor-opentelemetry
distro the platform uses, so records land in the Application Insights `traces` table with the
metric fields under customDimensions. OTel stamps each record with its real emission time, so
make-series / series_decompose see a genuine, evenly-spaced time series.

Usage (run from the platform/ folder, where .env lives):
    python seasonal_gen.py --minutes 12
    python seasonal_gen.py --minutes 15 --period 120
"""
import argparse
import logging
import math
import os
import random
import time

from dotenv import load_dotenv
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import _logs


def log(msg):
    """Print a timestamped progress line to the console immediately (unbuffered)."""
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


log("Loading .env and reading APPLICATIONINSIGHTS_CONNECTION_STRING ...")
load_dotenv()              # reads APPLICATIONINSIGHTS_CONNECTION_STRING from platform/.env

conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
if conn:
    log(f"Connection string found (len={len(conn)}). Configuring Azure Monitor exporter ...")
else:
    log("WARNING: APPLICATIONINSIGHTS_CONNECTION_STRING is not set — records will NOT reach App Insights. "
        "Run 'pwsh azure\\provision-observability.ps1' first to write platform/.env.")

configure_azure_monitor()
log("Azure Monitor configured. OpenTelemetry log pipeline is ready.")

logger = logging.getLogger("checkout_volume")
logger.setLevel(logging.INFO)

# Series shape. The benign seasonal PEAK stays BELOW a naive static alarm of 90, so the injected
# anomalies — not the normal busy period — are what actually matters.
BASE       = 50.0          # mid-line of the wave (checkouts/min)
AMPLITUDE  = 25.0          # peak ~75, trough ~25 before noise -> benign peak < 90
NOISE_SD   = 2.5           # gaussian jitter
STEP_SECS  = 10.0          # one sample every ~10 s


def emit_sample(val):
    """Emit one checkout-volume sample as a structured log record -> App Insights `traces`."""
    logger.info("checkout volume sample", extra={
        "signal_type":       "checkout_volume",
        "service":           "order-service",
        "checkouts_per_min": round(val, 2),
    })


def build_series(minutes, period):
    total_secs = minutes * 60.0
    n = max(int(total_secs / STEP_SECS), 1)

    # Inject two off-pattern events at fixed fractions of the run so they're reproducible:
    #   - a COLLAPSE in a quieter window (still < 90, so a static "too-high" threshold misses it)
    #   - a SURGE that briefly exceeds the seasonal peak (abnormal for that point in the cycle)
    collapse_idx = int(n * 0.45)
    surge_idx    = int(n * 0.75)

    log(f"Emitting {n} samples, one every {STEP_SECS:.0f}s "
        f"(~{minutes} min total). Injected COLLAPSE at sample #{collapse_idx + 1}, "
        f"SURGE at sample #{surge_idx + 1}.")

    for i in range(n):
        t = i * STEP_SECS
        val = BASE + AMPLITUDE * math.sin(2.0 * math.pi * t / period) + random.gauss(0.0, NOISE_SD)
        tag = ""
        if i == collapse_idx:
            val -= 22.0        # sudden collapse: abnormal for the cycle, but value stays well under 90
            tag = "  <-- injected COLLAPSE"
        elif i == surge_idx:
            val += 28.0        # sudden surge above the seasonal envelope
            tag = "  <-- injected SURGE"
        emit_sample(val)
        log(f"  sample {i + 1:>3}/{n}  checkouts_per_min={round(val, 2):>6}{tag}")
        if i < n - 1:          # no need to wait after the last sample
            time.sleep(STEP_SECS)

    log(f"Done emitting {n} samples.")


def main():
    ap = argparse.ArgumentParser(description="Emit a short synthetic seasonal checkout-volume series.")
    ap.add_argument("--minutes", type=int, default=12,
                    help="how many minutes of data to emit (default 12)")
    ap.add_argument("--period", type=float, default=120.0,
                    help="seasonal period in seconds (default 120 -> several cycles in 12 min)")
    args = ap.parse_args()

    log(f"Starting run: minutes={args.minutes}, period={int(args.period)}s, step={STEP_SECS:.0f}s")
    build_series(args.minutes, args.period)

    log("Flushing OpenTelemetry exporter (force_flush, up to 15s) to push records to App Insights ...")
    _logs.get_logger_provider().force_flush(timeout_millis=15000)   # ensure export
    log("Flush complete.")

    print(f"Emitted ~{int(args.minutes * 60 / STEP_SECS)} checkout-volume samples over "
          f"{args.minutes} min (period {int(args.period)} s). "
          "Allow 2-5 min for ingestion, then query the `traces` table.")


if __name__ == "__main__":
    main()
