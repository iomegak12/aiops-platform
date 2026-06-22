"""Simulated SQL database (the `db` topology node).

Healthy: a few ms per query. Under `failover`: latency spikes to seconds and ~60% of queries
error — the root cause of the recurring cascade. Every call emits a CLIENT span, so it shows
up as a dependency in Application Insights.
"""
import random
import time

from opentelemetry import trace
from opentelemetry.trace import SpanKind, Status, StatusCode

from .faults import get_fault

_tracer = trace.get_tracer("contoso.db")


def query(operation: str = "SELECT", table: str = "orders"):
    mode = get_fault("db")
    with _tracer.start_as_current_span(f"db {operation} {table}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("db.system", "contoso-sql")
        span.set_attribute("db.operation", operation)
        span.set_attribute("db.sql.table", table)
        span.set_attribute("db.fault", mode)
        if mode == "failover":
            time.sleep(random.uniform(0.8, 2.0))
            if random.random() < 0.60:
                span.set_status(Status(StatusCode.ERROR, "db failover: connection reset"))
                raise RuntimeError("db failover: connection reset")
        else:
            time.sleep(random.uniform(0.005, 0.030))
        return {"table": table, "operation": operation, "rows": random.randint(1, 5)}
