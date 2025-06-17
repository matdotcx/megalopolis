FROM python:3.11-slim

LABEL description="Minimal VM Operator - HTTP API wrapper for Tart VM management"
LABEL maintainer="megalopolis"

# Create non-root user
RUN groupadd -r vmoperator && useradd -r -g vmoperator vmoperator

# Set working directory
WORKDIR /app

# Copy the VM API script
COPY scripts/minimal-vm-api.py /app/vm-api.py

# Copy tart binary (will be mounted from host)
# Note: tart binary needs to be available at runtime
RUN mkdir -p /app/bin

# Install any additional Python dependencies if needed
# (Currently the script only uses standard library)

# Create directory for logs
RUN mkdir -p /app/logs && chown vmoperator:vmoperator /app/logs

# Switch to non-root user
USER vmoperator

# Expose the API port
EXPOSE 8082

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8082/health')" || exit 1

# Run the VM API server
CMD ["python3", "/app/vm-api.py"]