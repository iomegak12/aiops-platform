"""Payment Service — charges a payment. The flaky downstream of the estate.

Baseline ~10% of charges fail (simulated gateway timeout); under the `payment=outage` fault
almost all fail. Persists each charge to the simulated db, so a db `failover` also breaks
payments — that is the first visible symptom of the cascade.
"""
import os
import random
import sys

# Make the platform root importable regardless of how this is launched.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from telemetry import init_telemetry
tracer, meter, logger = init_telemetry("payment-service")  # MUST run before importing FastAPI

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

from deps import db
from deps.faults import get_fault

app = FastAPI(title="payment-service", version="1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

charges = meter.create_counter("payments_charged", description="payments charged")


class ChargeRequest(BaseModel):
    order_id: str
    amount_usd: float


@app.post("/charge")
def charge(req: ChargeRequest):
    with tracer.start_as_current_span("charge_payment"):
        db.query("INSERT", "payments")  # may raise under db failover
        mode = get_fault("payment")
        fail_p = {"healthy": 0.0, "baseline": 0.10, "outage": 0.85}.get(mode, 0.10)
        if random.random() < fail_p:
            logger.error("payment failed: gateway timeout for order %s", req.order_id)
            from fastapi import HTTPException
            raise HTTPException(status_code=502, detail="payment gateway timeout")
        charges.add(1)
        logger.info("payment charged: $%.2f for order %s", req.amount_usd, req.order_id)
        return {"status": "charged", "order_id": req.order_id, "amount_usd": req.amount_usd}


@app.get("/healthz")
def healthz():
    return {"status": "healthy", "service": "payment-service"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "5001")), use_colors=False)
