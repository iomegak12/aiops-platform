"""Order Service — the checkout path and the storefront's front door (the `api` node).

A checkout fans out to: inventory (HTTP) -> payment (HTTP) -> db write -> queue publish.
Because every hop is instrumented and trace context propagates, one checkout becomes a single
end-to-end operation across services — the multi-service trace the labs correlate.

Also hosts the admin/fault control surface the storefront's "chaos" panel calls, so an
instructor can inject db-failover / cache-eviction / queue-lag / payment-outage live.
"""
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from telemetry import init_telemetry
tracer, meter, logger = init_telemetry("order-service")  # before FastAPI import

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
import uvicorn

from deps import db, queue
from deps.faults import get_faults, set_fault, reset_faults

PAYMENT_URL = os.getenv("PAYMENT_URL", "http://localhost:5001")
INVENTORY_URL = os.getenv("INVENTORY_URL", "http://localhost:5002")

app = FastAPI(title="order-service", version="2.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

orders_processed = meter.create_counter("orders_processed", description="orders processed")
order_value = meter.create_histogram("order_value_usd", description="order value (USD)")

_client = httpx.Client(timeout=10.0)


class OrderRequest(BaseModel):
    sku: str = "SKU-001"
    amount_usd: float = 49.99


@app.post("/order")
def order(req: OrderRequest):
    order_id = f"ord-{uuid.uuid4().hex[:8]}"
    with tracer.start_as_current_span("process_order"):
        # 1. Inventory check (downstream service call)
        inv = _client.get(f"{INVENTORY_URL}/stock/{req.sku}")
        inv.raise_for_status()
        if not inv.json().get("in_stock", False):
            logger.info("order %s rejected: %s out of stock", order_id, req.sku)
            raise HTTPException(status_code=409, detail="out of stock")

        # 2. Payment charge (downstream service call — the flaky one)
        pay = _client.post(f"{PAYMENT_URL}/charge",
                           json={"order_id": order_id, "amount_usd": req.amount_usd})
        if pay.status_code != 200:
            logger.error("order %s failed: payment declined (%s)", order_id, pay.status_code)
            raise HTTPException(status_code=502, detail="payment failed")

        # 3. Persist + 4. emit async event
        db.query("INSERT", "orders")
        queue.publish("order-events", {"order_id": order_id, "type": "created"})

        orders_processed.add(1)
        order_value.record(req.amount_usd)
        logger.info("order processed: %s $%.2f", order_id, req.amount_usd)
        return {"status": "ok", "order_id": order_id, "amount_usd": req.amount_usd}


@app.post("/refund")
def refund(req: OrderRequest):
    with tracer.start_as_current_span("process_refund"):
        db.query("UPDATE", "orders")
        queue.publish("order-events", {"type": "refunded"})
        logger.info("refund processed for %s", req.sku)
        return {"status": "refunded", "sku": req.sku}


@app.get("/healthz")
def healthz():
    return {"status": "healthy", "service": "order-service"}


# ── Admin / chaos control (shared fault state for the whole estate) ──────────
class FaultRequest(BaseModel):
    target: str   # db | cache | queue | payment
    mode: str     # e.g. failover | eviction | lag | outage | healthy | baseline


@app.get("/admin/faults")
def admin_get_faults():
    return get_faults()


@app.post("/admin/fault")
def admin_set_fault(req: FaultRequest):
    logger.info("CHAOS: set %s = %s", req.target, req.mode)
    return set_fault(req.target, req.mode)


@app.post("/admin/reset")
def admin_reset():
    logger.info("CHAOS: reset all faults")
    return reset_faults()


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "5000")), use_colors=False)
