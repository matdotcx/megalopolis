# Megalopolis Usage Examples

Practical examples for deploying and managing the unified Kind + Tart homelab.

## 🚀 Quick Start Examples

### Complete Setup (128GB System)
```bash
# Full automated setup
make deploy-full

# Manual step-by-step
make ensure-tools
make init
make auto-provision
make comprehensive-status
```

### Daily Operations
```bash
# Check everything at once
make comprehensive-status

# Quick status check
make status

# Check VM health
make vm-health

# List all VMs
make vms
```

## 🖥️ VM Management Examples

### Creating Development Environments

```bash
# Create high-performance development VM
make vm-create VM_NAME=alice-dev VM_CONFIG=macos-dev-pro.yaml

# Create multiple developer VMs
for dev in alice bob charlie; do
    make vm-create VM_NAME=${dev}-dev VM_CONFIG=macos-dev-pro.yaml
done

# Create specialized VMs
make vm-create VM_NAME=ios-simulator VM_CONFIG=macos-simulator-farm.yaml
make vm-create VM_NAME=ci-runner VM_CONFIG=macos-ci-farm.yaml
```

### CI/CD Farm Setup

```bash
# Create CI farm for parallel builds
for i in {1..4}; do
    make vm-create VM_NAME=ci-worker-$i VM_CONFIG=macos-ci-farm.yaml
done

# Check CI farm status
make vm-health | grep ci-worker
```

### VM Operations

```bash
# Connect to a VM via SSH
make vm-connect VM_NAME=alice-dev

# Check VM IP and connectivity
./tart-binary ip alice-dev
ssh admin@$(./tart-binary ip alice-dev)

# VM lifecycle
./scripts/setup-vms.sh start alice-dev
./scripts/setup-vms.sh stop alice-dev
./scripts/setup-vms.sh delete alice-dev
```

## ☸️ Kubernetes Examples

### Cluster Management

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Access ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access Orchard Controller
kubectl port-forward -n orchard-system svc/orchard-controller 8081:8080
# Open http://localhost:8081
```

### Deploy Applications

```bash
# Example: Deploy a development application
cat > dev-app.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dev-app
  template:
    metadata:
      labels:
        app: dev-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: dev-app
  namespace: default
spec:
  selector:
    app: dev-app
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
EOF

kubectl apply -f dev-app.yaml
```

## 🔄 Automation Examples

### Automated Provisioning

```bash
# Provision VMs based on available resources
make auto-provision

# Dry-run to see what would be created
./scripts/auto-provision-vms.sh --dry-run

# Scale up infrastructure
make auto-provision
```

### Monitoring Setup

```bash
# Start continuous monitoring
make monitoring

# Check logs
tail -f /tmp/megalopolis-status.log

# Stop monitoring
pkill -f 'megalopolis.*monitoring'
```

### Health Checks and Maintenance

```bash
# Comprehensive validation
make validate

# VM health checks
make vm-health

# Check system resources
./scripts/comprehensive-status.sh
```

## 📊 Resource Management Examples

### Resource Planning (128GB System)

```bash
# Current allocation example:
# Host OS: 8GB reserved
# Kind cluster: 40GB (4 nodes × 10GB each)
# Development VMs: 48GB (3 × 16GB VMs)
# CI VMs: 24GB (3 × 8GB VMs)
# Simulator farm: 12GB (1 × 12GB VM)
# Buffer: 16GB available

# Check current resource usage
sysctl hw.memsize  # Total RAM
vm_stat | head -10  # Memory stats
docker stats --no-stream  # Container usage
```

### Scaling Strategies

```bash
# Scale up when resources available
if [ $(vm_stat | awk '/free/ {print $3}' | head -1) -gt 1000000 ]; then
    make auto-provision
fi

# Scale down idle VMs
./tart-binary list | grep stopped | head -2 | awk '{print $1}' | \
  xargs -I {} ./scripts/setup-vms.sh delete {}
```

## 🧪 Development Workflows

### iOS Development Pipeline

```bash
# 1. Setup development environment
make vm-create VM_NAME=ios-dev VM_CONFIG=macos-dev-pro.yaml

# 2. Setup CI environment
make vm-create VM_NAME=ios-ci VM_CONFIG=macos-ci-farm.yaml

# 3. Connect and setup project
make vm-connect VM_NAME=ios-dev
# In VM: git clone your iOS project
# In VM: open Xcode project

# 4. Run automated builds
ssh admin@$(./tart-binary ip ios-ci) "cd ~/CI && ./build-ios.sh"
```

### Multi-Developer Setup

```bash
# Create team development infrastructure
developers=("alice" "bob" "charlie" "diana")

for dev in "${developers[@]}"; do
    echo "Setting up environment for $dev..."
    
    # Create personal development VM
    make vm-create VM_NAME=${dev}-dev VM_CONFIG=macos-dev-pro.yaml
    
    # Wait for VM to boot
    sleep 60
    
    # Configure VM for developer
    vm_ip=$(./tart-binary ip ${dev}-dev)
    ssh admin@$vm_ip "
        git config --global user.name '$dev'
        git config --global user.email '${dev}@company.com'
        mkdir -p ~/Development/${dev}
    "
done
```

### Testing Infrastructure

```bash
# Create simulator farm for testing
make vm-create VM_NAME=test-farm VM_CONFIG=macos-simulator-farm.yaml

# Setup automated testing
vm_ip=$(./tart-binary ip test-farm)
ssh admin@$vm_ip "
    # Boot common simulators
    xcrun simctl boot 'iPhone 15 Pro'
    xcrun simctl boot 'iPad Pro (12.9-inch) (6th generation)'
    
    # Run automated tests
    cd ~/Simulators
    ./run-ui-tests.sh
"
```

## 🔧 Troubleshooting Examples

### Common Issues and Solutions

```bash
# Issue: VM won't start
./tart-binary list  # Check VM status
./scripts/setup-vms.sh start vm-name  # Try to start
./tart-binary delete vm-name  # Delete and recreate if needed

# Issue: SSH connection fails
./tart-binary ip vm-name  # Get VM IP
ping $(./tart-binary ip vm-name)  # Test connectivity
ssh -v admin@$(./tart-binary ip vm-name)  # Verbose SSH debug

# Issue: Cluster pods pending
kubectl get pods -A | grep Pending
kubectl describe pod <pending-pod> -n <namespace>
kubectl get nodes -o wide  # Check node status

# Issue: Resource exhaustion
docker stats --no-stream  # Check container usage
./scripts/comprehensive-status.sh  # Full resource view
make vm-health  # Check VM resource usage
```

### Cleanup and Reset

```bash
# Clean slate - remove everything
make clean

# Selective cleanup
./tart-binary list | grep stopped | awk '{print $1}' | \
  xargs -I {} ./scripts/setup-vms.sh delete {}

# Reset cluster only
make delete-cluster
make create-cluster
make bootstrap

# Reset VMs only
./tart-binary list | awk 'NR>1 {print $1}' | \
  xargs -I {} ./scripts/setup-vms.sh delete {}
```

## 📈 Performance Optimization

### High-Performance Configuration

```bash
# Optimize for development workloads
cat > tart/vm-configs/macos-dev-ultra.yaml << 'EOF'
name: "macos-dev-ultra"
base_image: "macos-sequoia"
description: "Ultra high-performance development VM"

resources:
  memory: "24576"  # 24GB RAM
  disk: "200"      # 200GB disk
  cpu: "12"        # 12 CPU cores

settings:
  ssh_enabled: true
  vnc_enabled: true
  hardware_acceleration: true
  auto_start: true
EOF

# Create ultra-performance VM
make vm-create VM_NAME=ultra-dev VM_CONFIG=macos-dev-ultra.yaml
```

### Resource Monitoring

```bash
# Setup metrics collection
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Monitor in real-time
watch -n 5 'make comprehensive-status'

# Resource usage tracking
while true; do
    echo "$(date): $(docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}')" >> resource-usage.log
    sleep 300
done &
```

## 🚀 Advanced Automation

### Infrastructure as Code

```bash
# Export current VM configuration
./scripts/setup-vms.sh list > current-vms.txt

# Backup VM configurations
tar -czf vm-configs-backup.tar.gz tart/vm-configs/

# Automated deployment script
cat > deploy-infrastructure.sh << 'EOF'
#!/bin/bash
set -e

echo "Deploying Megalopolis infrastructure..."

# Ensure tools
make ensure-tools

# Setup cluster
make init

# Deploy VMs based on team size
TEAM_SIZE=${1:-5}
for i in $(seq 1 $TEAM_SIZE); do
    make vm-create VM_NAME=dev-$i VM_CONFIG=macos-dev-pro.yaml
done

# Deploy CI infrastructure
for i in {1..3}; do
    make vm-create VM_NAME=ci-$i VM_CONFIG=macos-ci-farm.yaml
done

echo "Infrastructure deployment completed!"
make comprehensive-status
EOF

chmod +x deploy-infrastructure.sh
./deploy-infrastructure.sh 5  # Deploy for 5-person team
```

This comprehensive set of examples shows how to leverage the full power of your 128GB system with Megalopolis!