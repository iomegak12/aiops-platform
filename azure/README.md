# platform/azure — Azure provisioning scripts

Self-contained PowerShell Core scripts for the lab's Azure resources. Each one is **idempotent**
(checks whether resources already exist and skips), **dependency-aware**, **self-explaining** (it
narrates each step in the console), and **standalone** (no shared helper file, no reliance on
variables set by another script). Run any of them from anywhere — paths are derived from the
script location.

> Resource provisioning is a prerequisite for the Azure-connected labs (L1+). Run
> `provision-observability.ps1` once; re-run it any later day to refresh `../.env`.

| Script | What it does | Destructive? |
|--------|--------------|--------------|
| `provision-observability.ps1` | Sign-in check → `application-insights` extension → resource group → Log Analytics workspace → workspace-based App Insights → **merges** `platform/.env` (writes the connection string + `LAW_WORKSPACE_ID`, keeps your other keys). Idempotent; **re-running = re-bootstrap**. | No |
| `create-fastburn-alert.ps1` | Creates/updates the M2 fast-burn SLO alert (Sev1, 14.4× burn). Ensures its own `scheduled-query` extension; resolves the App Insights id. | No |
| `teardown.ps1` | Deletes the entire lab resource group. Requires typed confirmation (`-Force` to skip). | **Yes** |

> This is the **Block A slice** — only the scripts the foundation labs M0–M2 run (observability +
> the fast-burn alert + teardown). The embedding/chat model provisioning and the storm-suppression
> rule live with the Module 3 & 4 agentic labs, which provision their own Azure via
> `agentic-labs/scripts/initialize-lab-env.ps1` and the per-lab `provision-*.ps1`.

## Usage

```powershell
# Provision (or refresh) the observability plane and write platform/.env
pwsh provision-observability.ps1
pwsh provision-observability.ps1 -ResourceGroup my-rg -Location westeurope -Force

# Create the fast-burn alert (M2)
pwsh create-fastburn-alert.ps1 -ResourceGroup rg-aiops-lab -AppInsightsName appi-aiops

# End-of-course cleanup (irreversible)
pwsh teardown.ps1
```

Prerequisites: **Azure CLI (`az`)**, **PowerShell Core (`pwsh`)**, and an Azure subscription with
Contributor rights. Sign in first with `az login` — `provision-observability.ps1` aborts with a warning if you're not signed in.
