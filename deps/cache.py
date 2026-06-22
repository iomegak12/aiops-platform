"""Simulated cache (the `cache` topology node).

Healthy: fast, high hit rate. Under `eviction`: forced misses (callers fall back to db) and
added latency — the cache-eviction storm. Emits a CLIENT span per access.
"""
import random
import time

from opentelemetry import trace
from opentelemetry.trace import SpanKind

from .faults import get_fault

_tracer = trace.get_tracer("contoso.cache")


def get(key: str) -> bool:
    """Return True on cache hit, False on miss. Under eviction, almost always a miss."""
    mode = get_fault("cache")
    with _tracer.start_as_current_span(f"cache GET {key}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("db.system", "contoso-cache")
        span.set_attribute("cache.fault", mode)
        if mode == "eviction":
            time.sleep(random.uniform(0.05, 0.20))
            hit = random.random() < 0.05
        else:
            time.sleep(random.uniform(0.001, 0.008))
            hit = random.random() < 0.85
        span.set_attribute("cache.hit", hit)
        return hit


def set(key: str) -> None:
    with _tracer.start_as_current_span(f"cache SET {key}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("db.system", "contoso-cache")
        time.sleep(random.uniform(0.001, 0.006))
