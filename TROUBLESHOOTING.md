# VM Operator Troubleshooting Guide

This guide helps diagnose and resolve common issues with the Megalopolis VM Operator across different deployment scenarios.

## Quick Diagnostics

Run these commands to quickly identify issues:

```bash
# Test the complete VM operator stack
bash tests/test-vm-operator-integration.sh

# Test Docker-specific functionality
bash tests/test-docker-vm-operations.sh

# Test Kubernetes deployment
bash tests/test-k8s-vm-operator.sh
```

## Common Issues by Component

### 1. CLI VM Management Issues

#### ❌ Tart binary not found

**Symptoms:**
```
Error: Tart binary not found or not executable: ./tart-binary
```

**Diagnosis:**
```bash
ls -la ./tart-binary
file ./tart-binary
```

**Solutions:**
```bash
# Download tart binary if missing
# Check https://github.com/cirruslabs/tart for latest release

# Make executable if needed
chmod +x ./tart-binary

# Verify it works
./tart-binary --version
```

#### ❌ VM operations fail

**Symptoms:**
```
VM "vm-name" is not running
Permission denied
```

**Diagnosis:**
```bash
# Check VM status
./tart-binary list

# Check VM storage
ls -la ~/.tart/

# Test VM readiness monitor
bash scripts/vm-readiness-monitor.sh status vm-name
```

**Solutions:**
```bash
# Ensure .tart directory exists and is writable
mkdir -p ~/.tart
chmod 755 ~/.tart

# Check VM configuration
./tart-binary inspect vm-name

# Try starting VM manually
./tart-binary run vm-name --no-graphics
```

### 2. VM API Server Issues

#### ❌ API server won't start

**Symptoms:**
```
Address already in use
Permission denied
Import errors
```

**Diagnosis:**
```bash
# Check if port is in use
lsof -i :8082

# Test Python dependencies
python3 -c "import json, subprocess, datetime"

# Check script permissions
ls -la scripts/minimal-vm-api.py
```

**Solutions:**
```bash
# Kill existing processes
pkill -f "minimal-vm-api.py"

# Use different port if needed
# Edit scripts/minimal-vm-api.py and change port = 8082

# Ensure Python 3 is available
python3 --version
```

#### ❌ API endpoints return errors

**Symptoms:**
```
HTTP 500: Internal server error
HTTP 404: Endpoint not found
Empty or invalid JSON responses
```

**Diagnosis:**
```bash
# Start API server with logging
python3 scripts/minimal-vm-api.py

# Test individual endpoints
curl http://localhost:8082/health
curl http://localhost:8082/vms
curl http://localhost:8082/vms/vm-name
```

**Solutions:**
```bash
# Check tart binary is accessible
ls -la ./tart-binary

# Verify VMs exist
./tart-binary list

# Check API server logs for specific errors
# Look for import errors, permission issues, or tart command failures
```

### 3. Docker Container Issues

#### ❌ Container build fails

**Symptoms:**
```
Error response from daemon
Build failed
Permission denied
```

**Diagnosis:**
```bash
# Check Docker is running
docker info

# Check Dockerfile syntax
docker build --no-cache -t test -f docker/vm-operator/Dockerfile .

# Check file permissions
ls -la docker/vm-operator/
```

**Solutions:**
```bash
# Ensure Docker daemon is running
# Check Docker Desktop or colima status

# Clean build cache
docker system prune

# Check available disk space
df -h
```

#### ❌ Volume mounting fails

**Symptoms:**
```
Error: mkdir: file exists
hostPath type check failed
Permission denied
```

**Diagnosis:**
```bash
# Test basic volume mounting
docker run --rm -v $(pwd)/tart-binary:/test:ro alpine ls -la /test

# Check file vs directory
file ./tart-binary
ls -la ~/.tart
```

**Solutions:**

**For Colima/Docker Desktop:**
```bash
# This is a known limitation - volume mounting files often fails
# Use Kubernetes deployment instead
kubectl apply -f k8s-manifests/
```

**For Native Docker:**
```bash
# Ensure proper permissions
chmod 644 ./tart-binary
chmod 755 ~/.tart

# Try directory mounting instead of file mounting
# Copy tart binary to a directory and mount the directory
```

**For Production:**
```bash
# Use init containers or sidecar patterns
# See k8s-manifests/README.md for alternatives
```

#### ❌ Container runs but VM operations fail

**Symptoms:**
```
VMs endpoint returns 500 error
Tart command not found
Permission denied inside container
```

**Diagnosis:**
```bash
# Check volume mounts inside container
docker exec <container-id> ls -la /app/bin/
docker exec <container-id> ls -la /home/vmoperator/.tart

# Test tart binary execution
docker exec <container-id> /app/bin/tart-binary --version
```

**Solutions:**
```bash
# Verify volume mounts work
docker run -v $(pwd)/tart-binary:/app/bin/tart-binary:ro megalopolis/vm-operator ls -la /app/bin/

# Check container user permissions
docker exec <container-id> id
docker exec <container-id> whoami

# Ensure tart binary is executable in container
docker exec <container-id> test -x /app/bin/tart-binary
```

### 4. Kubernetes Deployment Issues

#### ❌ Pod stuck in Pending

**Symptoms:**
```
Pod status: Pending
FailedScheduling events
```

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod -n orchard-system -l app=vm-operator

# Check node selector
kubectl get nodes --show-labels

# Check resources
kubectl describe nodes
```

**Solutions:**
```bash
# Fix node selector if needed
# Edit vm-operator-deployment.yaml nodeSelector

# Ensure sufficient resources
kubectl top nodes

# Check hostPath volumes exist on nodes
# For kind: kubectl exec -it kind-control-plane ls -la /path/to/tart-binary
```

#### ❌ Pod CrashLoopBackOff

**Symptoms:**
```
Pod status: CrashLoopBackOff
Container exit codes
```

**Diagnosis:**
```bash
# Check container logs
kubectl logs -n orchard-system -l app=vm-operator

# Check previous container logs
kubectl logs -n orchard-system -l app=vm-operator --previous

# Check container status
kubectl describe pod -n orchard-system -l app=vm-operator
```

**Solutions:**
```bash
# Common fixes:
# 1. Fix hostPath volume paths in deployment.yaml
# 2. Ensure tart binary is executable
# 3. Fix file permissions

# Test container directly
kubectl run test-vm-operator --image=megalopolis/vm-operator --rm -it -- /bin/bash
```

#### ❌ Service not accessible

**Symptoms:**
```
Connection refused
No endpoints available
```

**Diagnosis:**
```bash
# Check service configuration
kubectl get svc -n orchard-system vm-operator

# Check endpoints
kubectl get endpoints -n orchard-system vm-operator

# Check pod labels match service selector
kubectl get pods -n orchard-system --show-labels
```

**Solutions:**
```bash
# Use port forwarding for testing
kubectl port-forward -n orchard-system svc/vm-operator 8082:8082

# Check ingress controller if using ingress
kubectl get ingress -n orchard-system

# Verify pod is running and healthy
kubectl get pods -n orchard-system -l app=vm-operator
```

### 5. Network Connectivity Issues

#### ❌ External access fails

**Symptoms:**
```
curl: Connection refused
Timeout errors
```

**Diagnosis:**
```bash
# Test from inside cluster
kubectl run test-pod --image=alpine --rm -it -- sh
# Inside pod: wget -O- http://vm-operator.orchard-system:8082/health

# Check service type and ports
kubectl get svc -n orchard-system vm-operator -o yaml
```

**Solutions:**
```bash
# For local testing, use port forwarding
kubectl port-forward -n orchard-system svc/vm-operator 8082:8082

# For external access, configure ingress or LoadBalancer
# See vm-operator-service.yaml for ingress configuration

# Check firewall rules and network policies
```

## Environment-Specific Issues

### Colima Users

**Common Issues:**
- Volume mounting fails with "file exists" error
- Port forwarding doesn't work reliably
- Container networking limitations

**Solutions:**
```bash
# Use Kubernetes deployment instead of Docker
kubectl apply -f k8s-manifests/

# Or use CLI management directly
bash scripts/setup-vms.sh list
```

### Kind Users

**Common Issues:**
- HostPath volumes don't work (no host filesystem access)
- Image pull errors (image not loaded into cluster)

**Solutions:**
```bash
# Load images into kind cluster
kind load docker-image megalopolis/vm-operator:latest

# Use alternative deployment patterns (see k8s-manifests/README.md)
# Or use CLI management
```

### CI/CD Environments

**Common Issues:**
- No access to host VM storage
- Isolated container environment
- Limited Docker capabilities

**Solutions:**
```bash
# Use CLI-based VM management in CI/CD
./scripts/setup-vms.sh list
./scripts/setup-vms.sh start vm-name

# Or mock VM operations for testing
export MOCK_VMS=true
bash tests/test-vm-operator-integration.sh
```

## Debug Commands

### Get Comprehensive System State

```bash
#!/bin/bash
echo "=== VM Operator Debug Information ==="
echo "Date: $(date)"
echo ""

echo "=== Tart Binary ==="
ls -la ./tart-binary 2>/dev/null || echo "Not found"
./tart-binary --version 2>/dev/null || echo "Not executable"

echo "=== VM Storage ==="
ls -la ~/.tart/ 2>/dev/null || echo "Directory not found"

echo "=== VMs ==="
./tart-binary list 2>/dev/null || echo "Command failed"

echo "=== Docker ==="
docker --version 2>/dev/null || echo "Not available"
docker info 2>/dev/null | grep -E "(Server Version|Operating System)" || echo "Not accessible"

echo "=== Kubernetes ==="
./kubectl version --client 2>/dev/null || echo "kubectl not available"
./kubectl cluster-info 2>/dev/null || echo "No cluster access"

echo "=== VM Operator Pods ==="
./kubectl get pods -n orchard-system 2>/dev/null || echo "No pods or no access"

echo "=== VM Operator Service ==="
./kubectl get svc -n orchard-system vm-operator 2>/dev/null || echo "Service not found"

echo "=== Process Status ==="
ps aux | grep -E "(tart|vm-api|python)" | grep -v grep || echo "No VM-related processes"

echo "=== Network ==="
netstat -an | grep 8082 || echo "Port 8082 not in use"
```

### Test All Components

```bash
# Run all tests and save results
bash tests/test-vm-operator-integration.sh > /tmp/integration-test.log 2>&1
bash tests/test-docker-vm-operations.sh > /tmp/docker-test.log 2>&1
bash tests/test-k8s-vm-operator.sh > /tmp/k8s-test.log 2>&1

echo "Test results saved to /tmp/*-test.log"
echo "Review logs for specific failure details"
```

## Getting Help

1. **Run the diagnostic tests** first to identify the specific issue
2. **Check the logs** for detailed error messages
3. **Review the component-specific documentation** in each directory
4. **Check known limitations** for your environment (Docker/K8s/CI)
5. **Use CLI management** as fallback when containerized solutions fail

## Contributing

Found a new issue or solution? Please:
1. Document the symptoms and diagnosis steps
2. Provide working solutions when possible
3. Add test cases to validate the fix
4. Update this troubleshooting guide