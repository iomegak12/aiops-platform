"""Simulated message queue (the `queue` topology node).

Healthy: enqueue is near-instant. Under `lag`: enqueue slows and a backlog counter grows —
the async-backlog symptom. Emits a CLIENT span per publish.
"""
import random
import time
from itertools import count

from opentelemetry import trace
from opentelemetry.trace import SpanKind

from .faults import get_fault

_tracer = trace.get_tracer("contoso.queue")
_depth = count()  # monotonically increasing publish counter (stand-in for backlog)


def publish(topic: str, message: dict) -> int:
    mode = get_fault("queue")
    with _tracer.start_as_current_span(f"queue PUBLISH {topic}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("messaging.system", "contoso-queue")
        span.set_attribute("messaging.destination", topic)
        span.set_attribute("queue.fault", mode)
        if mode == "lag":
            time.sleep(random.uniform(0.3, 1.0))
        else:
            time.sleep(random.uniform(0.002, 0.010))
        seq = next(_depth)
        span.set_attribute("messaging.sequence", seq)
        return seq
