# Contributing — Contoso Commerce Cloud

This is the **platform** half of an AIOps course: a deliberately lightweight microservices estate
that the labs observe, diagnose, and heal. Contributions should keep it that way — small, readable,
and infrastructure-free.

## Guiding principles

1. **Zero infrastructure to install.** The db/cache/queue tier is *simulated in-process* (`deps/`)
   on purpose. Do not introduce a real Postgres/Redis/RabbitMQ dependency, or anything that needs
   a separate server to run the platform. It must start on a laptop with just `pip install`.
2. **Keep it a teaching surface, not a product.** Clarity beats cleverness. The code is read by
   learners — favour explicit, well-commented flows over abstraction.
3. **Telemetry stays optional.** Every service must run in **DEMO MODE** with no `.env`
   (no telemetry) *and* fully instrumented when `APPLICATIONINSIGHTS_CONNECTION_STRING` is present.
   Route all telemetry setup through `telemetry.py` / `init_telemetry()`.
4. **Respect the Block boundaries.** This repo is the **Block A slice** (foundation labs M0–M2).
   The alert-storm / correlation / clustering tooling belongs to the Module 3 & 4 agentic labs and
   lives under `agentic-labs/` — don't pull it in here.

## Getting set up

```powershell
pip install -r requirements.txt
pwsh scripts/start.ps1    # all four services + storefront; -Stop to shut down
```

See the [README](README.md) for the topology and ports, and [TROUBLESHOOTING](TROUBLESHOOTING.md)
if something won't start.

## Project layout

| Path | What lives there |
|------|------------------|
| `services/` | The four FastAPI services (order, payment, inventory, storefront) |
| `deps/` | Simulated, fault-injectable db / cache / queue + fault state |
| `telemetry.py` | Shared OpenTelemetry / Azure Monitor bootstrap (`init_telemetry`) |
| `storefront/` | Static web app (the demo UI) |
| `azure/` | Idempotent PowerShell provisioning scripts (observability, alerts, teardown) |
| `scripts/` | Launchers and load generators (Windows / PowerShell Core) — `start.ps1`, `start-container.ps1`, `load.ps1` |
| `seasonal_gen.py`, `scripts/load.ps1` | Business-activity generators |

## Coding conventions

- **Python**: target 3.12 (the known-good runtime). FastAPI + `uvicorn[standard]`, `httpx` for
  inter-service calls. Match the surrounding style — module-level functions, descriptive names,
  comments that explain *why*.
- **New services**: call `init_telemetry("<service-name>")` at the **top of the file, before
  importing FastAPI**, so the ASGI app is auto-instrumented. Read `PORT` from the environment.
- **Inter-service URLs**: take them from env vars (e.g. `PAYMENT_URL`, `INVENTORY_URL`) so the same
  code works under `scripts/start.ps1` (localhost) and `docker compose` (service names).
- **PowerShell**: scripts target **PowerShell Core (`pwsh`)** on Windows 11. Keep them idempotent,
  self-narrating, and standalone (no shared helper file). Azure scripts must check sign-in and skip
  work that's already done.
- **Faults**: new fault modes go through the shared state in `deps/faults.py` and `state/faults.json`
  so every service sees them, and must be clearable via `POST /admin/reset`.

## Before you open a PR

- [ ] Platform starts clean in **DEMO MODE** (no `.env`): `pwsh scripts/start.ps1`, storefront loads, a
      checkout succeeds.
- [ ] If you touched telemetry, it also works **with** a real connection string (services log
      `telemetry ON`, distinct nodes appear in the Application Map).
- [ ] Any new fault is injectable **and** clears via `POST /admin/reset` / `scripts/start.ps1 -Stop`.
- [ ] No secrets committed — `.env`, `azure/.provision-state.json`, and `state/` are git-ignored;
      keep them that way.
- [ ] `requirements.txt` updated if you added a dependency (and note in a comment which lab needs it).
- [ ] Docs updated — README for behaviour/topology changes, TROUBLESHOOTING for new failure modes.
- [ ] A line added to [CHANGELOG](CHANGELOG.md) under **Unreleased**.

## Commit & PR style

- Write focused commits with imperative messages (`add queue-lag fault`, `fix payment baseline rate`).
- Keep PRs scoped to one change. Explain *what* and *why* in the description, and how you verified it
  (the DEMO-mode smoke test above is the baseline).
