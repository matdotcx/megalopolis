# Megalopolis Test Suite

This directory contains comprehensive automated tests to validate the Megalopolis infrastructure after deployment.

## Expected End State

Starting from a blank macOS installation, the Megalopolis setup should result in:

### Kubernetes Infrastructure
- **Kind cluster** named "homelab" running in Docker
- **Control plane** accessible on port 6443
- **Kubeconfig** properly configured at `~/.kube/config`

### Core Services
1. **ArgoCD** (GitOps)
   - Namespace: `argocd`
   - Access: Port-forward to localhost:8080
   - Admin credentials available in secret

2. **Orchard Controller** (VM Management)
   - Namespace: `orchard-system`
   - Access: Port-forward to localhost:8081 or NodePort 30080
   - Manages Tart VMs from Kubernetes

### Virtual Machines
- **macos-dev**: Development environment (SSH port 2222, VNC 5900)
- **macos-ci**: CI environment (SSH port 2223, headless)
- Both VMs running macOS Sequoia with development tools

### Additional Namespaces
Created for future service deployment:
- `cert-manager` - TLS certificate management
- `ingress-nginx` - Ingress controller
- `external-secrets` - Secret management
- `monitoring` - Observability stack
- `keycloak` - Identity provider

## Test Scripts

### 1. Infrastructure State Test (`test-infrastructure-state.sh`)
Validates the basic infrastructure components:
- Docker availability and running state
- Kind cluster existence and health
- kubectl configuration and connectivity
- Tart binary installation and functionality
- Expected VMs existence
- Network configuration

### 2. Kubernetes Services Test (`test-kubernetes-services.sh`)
Tests Kubernetes cluster and services:
- Cluster connectivity and node readiness
- All expected namespaces exist
- ArgoCD pods running and accessible
- Orchard controller running and accessible
- Service endpoints responding correctly

### 3. VM Connectivity Test (`test-vm-connectivity.sh`)
Validates virtual machine infrastructure:
- VM existence and running state
- IP address assignment
- SSH connectivity and authentication
- Port forwarding functionality
- Basic command execution in VMs

### 4. End-to-End Validation (`test-e2e-validation.sh`)
Tests infrastructure integration:
- VM to Kubernetes communication
- ArgoCD GitOps capabilities
- Orchard VM management integration
- Resource allocation validation
- Service mesh readiness

### 5. Test Runner (`run-all-tests.sh`)
Orchestrates all tests:
- Pre-flight checks for required tools
- Runs all test suites in sequence
- Generates comprehensive test report
- Provides pass/fail summary

## Running Tests

### Run All Tests
```bash
cd tests
./run-all-tests.sh
```

### Run Individual Tests
```bash
# Test infrastructure state
./test-infrastructure-state.sh

# Test Kubernetes services
./test-kubernetes-services.sh

# Test VM connectivity
./test-vm-connectivity.sh

# Test end-to-end integration
./test-e2e-validation.sh
```

### Integration with Makefile
The test suite is integrated with the main Makefile:
```bash
# Run full automation test (clean install + validation)
make test-automation

# Just validate existing infrastructure
make validate
```

## Test Reports

Test execution generates timestamped reports in the `tests/` directory:
- `test-report-YYYYMMDD-HHMMSS.txt` - Summary of test results
- Console output shows real-time test progress with color coding

## Success Criteria

The infrastructure is considered fully operational when:
1. All pre-flight checks pass (tools available)
2. Infrastructure state test passes (Docker, Kind, Tart working)
3. Kubernetes services test passes (cluster healthy, services running)
4. VM connectivity test passes (VMs accessible via SSH)
5. End-to-end validation passes (integration working)

## Troubleshooting

If tests fail:

1. **Infrastructure State Failures**
   - Ensure Docker Desktop is running
   - Check if Kind cluster exists: `./kind-binary get clusters`
   - Verify Tart installation: `./tart-binary list`

2. **Kubernetes Service Failures**
   - Check pod status: `./kubectl get pods -A`
   - View pod logs: `./kubectl logs -n <namespace> <pod-name>`
   - Ensure cluster is running: `docker ps | grep kind`

3. **VM Connectivity Failures**
   - List VMs: `./tart-binary list`
   - Check VM status: `make vm-status`
   - Try manual SSH: `ssh admin@<vm-ip>`

4. **End-to-End Failures**
   - Check service endpoints are accessible
   - Verify network connectivity between components
   - Review Orchard controller logs for VM management issues

## Continuous Validation

For ongoing monitoring:
```bash
# Start continuous monitoring (runs every 5 minutes)
make monitoring

# Check comprehensive status
make comprehensive-status
```