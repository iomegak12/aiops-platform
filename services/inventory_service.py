"""Inventory Service — checks/reserves stock. Reads cache first, falls back to db on a miss.

Cache `eviction` forces db fallback on every check (slower, more db load); db `failover`
then makes those fallbacks fail — so inventory degrades during the cascade too.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from telemetry import init_telemetry
tracer, meter, logger = init_telemetry("inventory-service")  # before FastAPI import

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from deps import db, cache

app = FastAPI(title="inventory-service", version="1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/stock/{sku}")
def stock(sku: str):
    with tracer.start_as_current_span("check_stock"):
        hit = cache.get(f"stock:{sku}")
        if not hit:
            db.query("SELECT", "inventory")  # cache miss -> hit the db (may fail under failover)
            cache.set(f"stock:{sku}")
        in_stock = random.random() < 0.95
        logger.info("stock check sku=%s in_stock=%s (cache_hit=%s)", sku, in_stock, hit)
        return {"sku": sku, "in_stock": in_stock, "cache_hit": hit}


@app.get("/healthz")
def healthz():
    return {"status": "healthy", "service": "inventory-service"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "5002")), use_colors=False)
