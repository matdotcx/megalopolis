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

## Configuration

The container expects:

1. **Tart binary** mounted at `/app/bin/tart-binary`
2. **VM storage** mounted at `/home/vmoperator/.tart`
3. **Port 8082** exposed for API access

## Security Notes

- Container runs as non-root user `vmoperator`
- Tart binary is mounted read-only
- VM storage directory requires read-write access
- Health checks validate API responsiveness

## Troubleshooting

### Container won't start
- Verify tart binary exists and is executable
- Check volume mount permissions
- Review logs: `docker-compose logs vm-operator`

### API not responding
- Verify port 8082 is accessible
- Check health check status: `docker-compose ps`
- Test direct connection: `docker exec vm-operator curl localhost:8082/health`

### VM operations fail
- Ensure tart binary has proper permissions
- Verify VM storage directory is writable
- Check that VMs exist in the mounted storage