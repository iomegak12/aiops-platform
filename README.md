# Contoso Commerce Cloud — the platform

The running estate the whole course observes, diagnoses, and heals. It's a **deliberately
lightweight** microservices platform: real services and real telemetry, but the db/cache/queue
tier is **simulated in-process** — so it runs on a laptop with zero infrastructure to install,
and the focus stays on **AIOps**, not on operating Postgres/Redis/RabbitMQ.

## The estate

```
        storefront-ui  :8080   (web app — served over HTTP)
               │  HTTP (fetch)
               ▼
        order-service  :5000   ──HTTP──▶  inventory-service :5002
        (api / checkout)        ──HTTP──▶  payment-service   :5001
               │                                   │
               ▼                                   ▼
   db (sim) · cache (sim) · queue (sim)   ← shared, fault-injectable, instrumented
```

| Service | Port | Calls | Topology node |
|---------|------|-------|----------------|
| storefront-ui | 8080 | order-service | (frontend) |
| order-service | 5000 | inventory, payment, db, queue | `api` |
| payment-service | 5001 | db | `db` (downstream) |
| inventory-service | 5002 | cache, db | `db`,`cache` |
| db / cache / queue (`deps/`) | — | (in-process) | `db` / `cache` / `queue` |

Every service is OpenTelemetry-instrumented; the simulated dependencies emit **CLIENT
(dependency) spans**, so with telemetry on they appear as distinct nodes in the Application
Map and one checkout becomes a single end-to-end trace (`order → payment → db`).

## Run it

```powershell
# from this folder:
pip install -r requirements.txt
pwsh scripts/start.ps1        # launches all four services (own windows) + opens the storefront
# storefront web app: http://localhost:8080   (its API base defaults to http://localhost:5000)
```

- **No `.env`** → the whole platform runs in **DEMO MODE** (Lab 0): fully functional, no telemetry.
- **With `.env`** holding `APPLICATIONINSIGHTS_CONNECTION_STRING` (Lab 1 writes it) → telemetry flows to Azure Monitor.

Stop everything: `pwsh scripts/start.ps1 -Stop`.

## Drive business activity

In the storefront: **Checkout** / **Refund** individual products, or hit **Auto-shop** for a
steady organic stream. The **Session stats** panel shows live success rate.

**Generators (headless):**
- `pwsh scripts/load.ps1` — fires a burst of checkouts at the order service (warm-up / load; used by L0, L2).
- `python seasonal_gen.py --minutes 12` — emits a short, compressed **seasonal checkout-volume** series into App Insights for the seasonality lab (M2 / Lab 2b). Reads `.env`; needs `pip install -r requirements.txt` first.

> This is the **Block A slice** of the platform — just what the foundation labs M0–M2 run. The alert-storm / correlation / severity tooling (`storm.py`, `severity.py`, `metric_correlation.py`, `alert_clustering.ipynb`) belongs to the Module 3 & 4 agentic labs, which re-implement those as their own per-lab modules under `agentic-labs/M3-*/` and `M4-*/`.

## Inject incidents (the chaos panel)

The storefront's **Chaos control** (or any `POST /admin/fault` on the order service) injects faults
into shared state that every service reads:

| Fault | Effect | The story |
|-------|--------|-----------|
| `db = failover` | db latency spikes to seconds, ~60% error → ripples to payment/inventory/order | **the recurring cascade** |
| `cache = eviction` | forced misses → db fallback, higher latency | the cache-eviction storm |
| `queue = lag` | slow publishes, growing backlog | async backlog |
| `payment = outage` | almost all charges fail | payment incident |
| `payment = baseline` | ~10% fail (default) | normal flakiness |

```powershell
# example via CLI instead of the UI:
curl -X POST http://localhost:5000/admin/fault -H "Content-Type: application/json" -d '{\"target\":\"db\",\"mode\":\"failover\"}'
curl -X POST http://localhost:5000/admin/reset
```

> Faults persist in `state/faults.json`; `scripts/start.ps1 -Stop` and `/admin/reset` clear them.
