# Changelog

All notable changes to the Contoso Commerce Cloud platform are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Project meta files: `.gitignore`, `TROUBLESHOOTING.md`, `CONTRIBUTING.md`, `CHANGELOG.md`.

### Changed
- Moved the root launcher/generator scripts (`start.ps1`, `start-container.ps1`, `load.ps1`) into
  `scripts/`; updated all references (README, docs, `.dockerignore`, `azure/` script hint) and the
  scripts' own root-path resolution accordingly. Run them as `pwsh scripts/start.ps1`.

## [0.1.0] — 2026-06-22

The **Block A slice** of the platform — everything the foundation labs M0–M2 run.

### Added
- **Microservices estate**: `order-service` (:5000), `payment-service` (:5001),
  `inventory-service` (:5002), and `storefront-ui` (:8080), all FastAPI + OpenTelemetry.
- **Simulated dependency tier** (`deps/`): in-process db, cache, and queue that emit CLIENT
  (dependency) spans — distinct nodes in the Application Map, zero infrastructure to install.
- **Shared telemetry bootstrap** (`telemetry.py` / `init_telemetry`): DEMO MODE with no `.env`,
  full Azure Monitor export (logs/traces/metrics, end-to-end trace correlation) when
  `APPLICATIONINSIGHTS_CONNECTION_STRING` is set.
- **Chaos control**: fault injection via the storefront panel or `POST /admin/fault`
  (`db=failover`, `cache=eviction`, `queue=lag`, `payment=outage`, `payment=baseline`), persisted in
  `state/faults.json` and cleared via `POST /admin/reset`.
- **Launchers**: `start.ps1` (all services + storefront, `-Stop` to shut down),
  `start-container.ps1`, `Dockerfile`, and `docker-compose.yml` (single `contoso-platform` image,
  shared state volume).
- **Business-activity generators**: `load.ps1` (checkout burst / warm-up) and `seasonal_gen.py`
  (compressed seasonal checkout-volume series for the seasonality lab).
- **Azure provisioning** (`azure/`): idempotent PowerShell scripts —
  `provision-observability.ps1` (Log Analytics + workspace-based App Insights, writes `.env`),
  `create-fastburn-alert.ps1` (M2 fast-burn SLO alert), and `teardown.ps1`.
- **Configuration template** (`.env.example`) and `requirements.txt`.

[Unreleased]: https://example.com/contoso-commerce-cloud/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/contoso-commerce-cloud/releases/tag/v0.1.0
