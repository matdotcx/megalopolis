# VM Operator Docker Container

This directory contains the Docker configuration for the Minimal VM Operator, which provides an HTTP API wrapper around Tart VM management.

## Features

- **HTTP API** for VM operations (list, start, stop, status)
- **Health checks** built-in for container orchestration
- **Non-root execution** for security
- **Volume mounts** for tart binary and VM storage

## API Endpoints

- `GET /health` - Health check endpoint
- `GET /vms` - List all VMs
- `GET /vms/{name}` - Get specific VM details  
- `POST /vms/{name}/start` - Start a VM
- `POST /vms/{name}/stop` - Stop a VM

## Quick Start

### Using Docker Compose

```bash
# Build and start the container
cd docker/vm-operator
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f

# Test the API
curl http://localhost:8082/health
curl http://localhost:8082/vms

# Stop the container
docker-compose down
```

### Using Docker CLI

```bash
# Build the image
docker build -t megalopolis/vm-operator -f docker/vm-operator/Dockerfile .

# Run the container
docker run -d \
  --name vm-operator \
  -p 8082:8082 \
  -v $(pwd)/tart-binary:/app/bin/tart-binary:ro \
  -v ~/.tart:/home/vmoperator/.tart:rw \
  megalopolis/vm-operator
```

## Requirements

- **Tart binary** must be available at the project root
- **Tart VM storage** directory (`~/.tart`) should exist
- **Network access** to the host for VM operations
- **Real Docker environment** (not containerized Docker like Colima)

## Configuration

The container expects:

1. **Tart binary** mounted at `/app/bin/tart-binary`
2. **VM storage** mounted at `/home/vmoperator/.tart`
3. **Port 8082** exposed for API access

## Known Limitations

### ⚠️ Volume Mounting Limitations

**Docker-in-Docker Environments:**
- **Colima** - File volume mounts fail with "file exists" error
- **Docker Desktop** (some configurations) - Limited host filesystem access
- **Kind clusters** - No access to host filesystem
- **CI/CD containers** - Isolated from host filesystem

**Working Environments:**
- **Native Docker** on Linux/macOS with direct host access
- **Docker Desktop** with proper volume sharing enabled
- **Real Kubernetes clusters** with hostPath volume support

### Test Results

Run the comprehensive test suite to validate your environment:

```bash
# Test Docker functionality
bash tests/test-docker-vm-operations.sh

# Test full integration
bash tests/test-vm-operator-integration.sh
```

**Expected Results:**
- ✅ Container builds and runs (health endpoint works)
- ❌ Volume mounting may fail in containerized Docker environments
- ✅ API functionality works when volumes mount successfully

## Security Notes

- Container runs as non-root user `vmoperator`
- Tart binary is mounted read-only
- VM storage directory requires read-write access
- Health checks validate API responsiveness

## Troubleshooting

### Container won't start
```bash
# Check if tart binary exists and is executable
ls -la ./tart-binary

# Try without volume mounts first
docker run -d -p 8082:8082 megalopolis/vm-operator

# Check container logs
docker logs <container-id>
```

### Volume mount failures
```bash
# Test volume mounting capability
docker run --rm -v $(pwd)/tart-binary:/test:ro alpine ls -la /test

# Error: "mkdir: file exists" indicates containerized Docker limitation
# Solution: Use Kubernetes deployment or native Docker environment
```

### API not responding
```bash
# Test health endpoint directly in container
docker exec <container-id> python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8082/health').read().decode())"

# Check port mapping
docker port <container-id>

# Test external access (may fail in some Docker environments)
curl http://localhost:8082/health
```

### VM operations fail
```bash
# Verify tart binary is accessible inside container
docker exec <container-id> ls -la /app/bin/tart-binary

# Test tart binary execution
docker exec <container-id> /app/bin/tart-binary list

# Check VM storage directory
docker exec <container-id> ls -la /home/vmoperator/.tart
```

### Environment-Specific Solutions

**For Colima users:**
- Volume mounting doesn't work reliably
- Use Kubernetes deployment instead
- Or use CLI management: `scripts/setup-vms.sh`

**For Kind users:**
- HostPath volumes don't work
- Use sidecar pattern or init containers
- Or use CLI management for VM operations

**For production:**
- Use real Kubernetes clusters with hostPath volumes
- Or deploy on Docker hosts with native filesystem access
- Monitor volume mount permissions and ownership