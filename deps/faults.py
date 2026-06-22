"""Cross-process fault state for the platform.

The services run as separate processes, so they share fault state through one JSON file
(platform/state/faults.json). The storefront's "chaos" panel (or any admin call) writes it;
every dependency reads it on each operation. Same machine, shared filesystem — the simplest
shared-state mechanism that lets a single db-failover cascade across all services at once.
"""
import json
from pathlib import Path

_STATE_FILE = Path(__file__).resolve().parent.parent / "state" / "faults.json"

# mode values:
#   db      : "healthy" | "failover"
#   cache   : "healthy" | "eviction"
#   queue   : "healthy" | "lag"
#   payment : "baseline" (~10% fail) | "healthy" (0%) | "outage" (mostly fail)
DEFAULTS = {"db": "healthy", "cache": "healthy", "queue": "healthy", "payment": "baseline"}


def get_faults() -> dict:
    try:
        return {**DEFAULTS, **json.loads(_STATE_FILE.read_text(encoding="utf-8"))}
    except Exception:
        return dict(DEFAULTS)


def get_fault(target: str) -> str:
    return get_faults().get(target, DEFAULTS.get(target, "healthy"))


def set_fault(target: str, mode: str) -> dict:
    faults = get_faults()
    faults[target] = mode
    _STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    _STATE_FILE.write_text(json.dumps(faults, indent=2), encoding="utf-8")
    return faults


def reset_faults() -> dict:
    _STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    _STATE_FILE.write_text(json.dumps(DEFAULTS, indent=2), encoding="utf-8")
    return dict(DEFAULTS)
