"""Storefront UI host — serves the business web app over HTTP (the `storefront` front end).

A thin static host so the storefront is a real web app at http://localhost:8080 rather than a
file:// page. It serves the contents of platform/storefront/ (index.html at the root). The UI
itself calls the order-service API at http://localhost:5000 (cross-origin; CORS is enabled there).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from telemetry import init_telemetry
tracer, meter, logger = init_telemetry("storefront-service")  # before FastAPI import

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import uvicorn

_STOREFRONT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "storefront"
)

app = FastAPI(title="storefront-ui", version="1.0")
app.mount("/", StaticFiles(directory=_STOREFRONT_DIR, html=True), name="storefront")


if __name__ == "__main__":
    print(f"[storefront-ui] serving {_STOREFRONT_DIR} on http://localhost:{os.getenv('PORT', '8080')}")
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8080")), use_colors=False)
