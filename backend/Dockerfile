# Production Dockerfile for Premises Backend
# Python 3.11 Slim for small image size
FROM python:3.11-slim as builder

# Set build-time environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies into a virtual environment or directly (builder stage)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# --- Final Stage ---
FROM python:3.11-slim

# Set runtime environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

WORKDIR /app

# Create a non-root user for security
RUN groupadd -r premises && useradd -r -g premises premises

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application source code
# We only copy the 'app' directory and other necessary files
COPY . /app
# If there are assets or static files, include them here.
# Based on analysis, we need 'app' package.

# Change ownership to non-root user
RUN chown -R premises:premises /app

# Switch to non-root user
USER premises

# Expose the production port
EXPOSE 8019

# Healthcheck to ensure the backend is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; import sys; try: urllib.request.urlopen('http://localhost:8019/health'); sys.exit(0); except: sys.exit(1)"

# Start FastAPI with Uvicorn
# Running with 4 workers is a good production starting point, but uvicorn --workers
# requires uvicorn[standard] which is in requirements.txt
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8019", "--proxy-headers", "--forwarded-allow-ips", "*"]
