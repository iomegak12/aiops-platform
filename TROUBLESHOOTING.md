# Troubleshooting — Contoso Commerce Cloud

Common issues when running the platform locally, and how to resolve them. The platform is
**deliberately infrastructure-free** (db/cache/queue are simulated in-process), so most problems
are about Python setup, ports, telemetry config, or fault state — not external services.

---

## Startup & processes

### `pwsh scripts/start.ps1` opens windows that immediately close
A service crashed on launch. Run the script directly to see the traceback:

```powershell
$env:PYTHONPATH = (Get-Location).Path
$env:PORT = "5000"
python services/order_service.py
```

Most common cause is a missing dependency — see [Dependencies](#dependencies).

### "No running platform services found" on `scripts/start.ps1 -Stop`
The PID file (`state/pids.txt`) is missing or was already cleared. If services are still bound to
ports, find and stop them manually:

```powershell
Get-NetTCPConnection -LocalPort 5000,5001,5002,8080 -State Listen |
    Select-Object LocalPort, OwningProcess
Stop-Process -Id <pid>
```

### `start.ps1` won't run — execution policy
PowerShell blocks unsigned scripts by default:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# or invoke explicitly:
pwsh -ExecutionPolicy Bypass -File start.ps1
```

---

## Ports

### `[Errno 10048] address already in use` (or `OSError: [WinError 10013]`)
Another process holds one of the platform ports (**5000** order, **5001** payment, **5002**
inventory, **8080** storefront). Identify and stop it:

```powershell
Get-NetTCPConnection -LocalPort 5000 -State Listen | Select-Object OwningProcess
Stop-Process -Id <pid>
```

Often it's a previous run that didn't shut down cleanly — try `pwsh start.ps1 -Stop` first.

---

## Dependencies

### `ModuleNotFoundError` (fastapi, uvicorn, azure-monitor-opentelemetry, …)
Dependencies aren't installed in the active interpreter:

```powershell
pip install -r requirements.txt
```

### `ModuleNotFoundError: No module named 'telemetry'` / `deps` / `services`
The repo root isn't on `PYTHONPATH`. `start.ps1` sets this for you; if you run a service by hand,
set it first:

```powershell
$env:PYTHONPATH = (Get-Location).Path
```

### `hdbscan` / `umap-learn` fail to install (Lab 4)
These need a C/C++ build toolchain and don't always have wheels for the newest Python. Use a
supported Python (3.12 is known-good here — the cached bytecode is `cpython-312`), and on Windows
install the **Microsoft C++ Build Tools** if a source build is triggered. These packages are only
needed for the Lab 4 clustering work, not for running the platform.

---

## Telemetry / Azure Monitor

### Services log `DEMO MODE - no APPLICATIONINSIGHTS_CONNECTION_STRING`
This is expected with no `.env` (Lab 0). The platform is fully functional; it just exports no
telemetry. To enable telemetry, create `.env` from the template and add a real connection string:

```powershell
Copy-Item .env.example .env
# then set APPLICATIONINSIGHTS_CONNECTION_STRING (Lab 1 / azure/provision-observability.ps1 writes it)
```

### `.env` is set but nothing appears in the Application Map
- Telemetry is read **at process start** — restart all services after editing `.env`.
- Allow a few minutes; Azure Monitor ingestion is not instant.
- Confirm the connection string is the full `InstrumentationKey=…;IngestionEndpoint=…` value, not
  just the key.
- Each service must come up with a distinct `OTEL_SERVICE_NAME` (set automatically per service) for
  separate nodes to appear.

### Services don't link into one end-to-end trace
Cross-service trace context relies on the httpx instrumentation. It's best-effort and silently
skipped if `opentelemetry-instrumentation-httpx` isn't installed — reinstall requirements.

---

## Faults & state

### Faults won't clear / a service stays broken after testing
Injected faults persist in `state/faults.json` and are shared across services. Reset them:

```powershell
curl -X POST http://localhost:5000/admin/reset
# or stop everything (also clears state):
pwsh start.ps1 -Stop
```

### Checkouts fail ~10% of the time with no fault injected
That's the intended `payment = baseline` flakiness (normal background error rate), not a bug.

---

## Docker

### `docker compose up` — services can't reach each other
Inside compose, services address each other by **name** (`http://payment:5001`,
`http://inventory:5002`), not `localhost`. These are wired via env vars in `docker-compose.yml`;
don't override them with `localhost`.

### Stale fault state across container restarts
Fault state lives in the named volume `platform-state`. To start clean:

```powershell
docker compose down -v
```

---

## Still stuck?
Run the failing service directly (see the first section) to get the full traceback, and check the
[README](README.md) for the expected topology, ports, and run commands.
