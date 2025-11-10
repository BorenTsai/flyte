# Dockerfile for Ray Lifecycle Test
# This container will be used by Flyte to run the Ray tasks on your cluster

FROM python:3.11-slim

WORKDIR /root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy test files
COPY test_ray_lifecycle.py .
COPY test_simple.py .

# Set Python path
ENV PYTHONPATH=/root:$PYTHONPATH

# This container will be used by Flyte to execute tasks
CMD ["python"]
