# Minimal single image for the whole Contoso Commerce Cloud platform.
# docker-compose runs four containers from this one image, each overriding `command`.
# No HEALTHCHECK by design.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install deps first for layer caching.
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy the platform code (see .dockerignore for what's excluded).
COPY . .

# Default command; compose overrides this per service.
CMD ["python", "services/order_service.py"]
