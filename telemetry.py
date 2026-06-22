"""Shared telemetry bootstrap for every Contoso Commerce Cloud service.

Call init_telemetry(service_name) at the TOP of each service, BEFORE importing FastAPI,
so the ASGI app is auto-instrumented. The same guard the labs teach applies here:

  - DEMO MODE (Lab 0): no APPLICATIONINSIGHTS_CONNECTION_STRING -> service runs, exports nothing.
  - INSTRUMENTED (Lab 1+): connection string present -> logs/traces/metrics flow to Azure Monitor,
    and OTEL_SERVICE_NAME makes each service a distinct node in the Application Map.
"""
import logging
import os

from opentelemetry import trace, metrics
from dotenv import load_dotenv


def init_telemetry(service_name: str):
    load_dotenv()  # load .env if present (Lab 1+); absent in Lab 0 demo mode

    # Distinct cloud role name per service -> separate nodes in the Application Map.
    os.environ.setdefault("OTEL_SERVICE_NAME", service_name)

    conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if conn:
        from azure.monitor.opentelemetry import configure_azure_monitor
        configure_azure_monitor(connection_string=conn)
        # Propagate trace context on outbound calls so order -> payment -> db links into one
        # end-to-end operation (the multi-service correlation the labs rely on).
        try:
            from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
            HTTPXClientInstrumentor().instrument()
        except Exception:  # instrumentation is best-effort; never block startup
            pass
        print(f"[{service_name}] telemetry ON - exporting logs/traces/metrics to Azure Monitor.")
    else:
        print(f"[{service_name}] DEMO MODE - no APPLICATIONINSIGHTS_CONNECTION_STRING; no telemetry export.")

    logger = logging.getLogger(service_name)
    logger.setLevel(logging.INFO)  # else INFO logs are dropped at the default WARNING level
    return trace.get_tracer(service_name), metrics.get_meter(service_name), logger
