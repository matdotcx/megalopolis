# Megalopolis Deployment Guide

Complete guide for deploying and scaling the unified Kind + Tart homelab on high-resource systems.

## Table of Contents
- [System Overview](#system-overview)
- [Resource Planning](#resource-planning)
- [Quick Start](#quick-start)
- [Advanced Deployment](#advanced-deployment)
- [VM Automation](#vm-automation)
- [Monitoring & Status](#monitoring--status)
- [Scaling Strategies](#scaling-strategies)
- [Production Workflows](#production-workflows)
- [Troubleshooting](#troubleshooting)

## System Overview

Megalopolis provides unified orchestration of:
- **Kubernetes cluster** (Kind) - Container workloads, GitOps, CI/CD
- **macOS VMs** (Tart) - iOS/macOS development, testing, builds
- **VM orchestration** (Orchard) - K8s-native VM lifecycle management

### Architecture on High-Resource Systems

```
M3 Mac (128GB RAM, Many Cores)
├── Kind Cluster (20-40GB RAM)
│   ├── Control Plane (4GB)
│   ├── Worker Nodes x3 (8GB each)
│   ├── ArgoCD + Platform Services (8GB)
│   └── Orchard Controller (2GB)
├── Development VMs (40-60GB RAM)
│   ├── macos-dev-1 (16GB) - Primary development
│   ├── macos-dev-2 (16GB) - Secondary/testing
│   └── macos-ci-1 (12GB) - CI/CD builds
├── CI/Build VMs (30-40GB RAM)
│   ├── macos-ci-2 (8GB) - Fast builds
│   ├── macos-ci-3 (8GB) - Parallel builds
│   └── macos-staging (16GB) - Release testing
└── Specialty VMs (20GB RAM)
    ├── macos-simulator (12GB) - iOS Simulator farm
    └── macos-legacy (8GB) - Legacy iOS versions
```

## Resource Planning

### Recommended Allocation (128GB System)
- **Host OS**: 8GB reserved
- **Kind Cluster**: 40GB (expandable)
- **Development VMs**: 48GB (3x 16GB VMs)
- **CI/Build VMs**: 24GB (3x 8GB VMs)
- **Buffer**: 8GB for overhead

### CPU Core Distribution
- **Kind cluster**: 8-12 cores
- **Each VM**: 2-4 cores (auto-scaling based on load)
- **Host processes**: 4 cores reserved

## Quick Start

### 1. Initial Setup
```bash
# Clone and enter directory
cd megalopolis

# Initialize everything (Kind cluster + default VMs)
make init

# Verify deployment
make validate
make status
```

### 2. Default VM Configuration
The system automatically creates:
- `macos-dev` (6GB RAM, 4 cores) - Development environment
- `macos-ci` (4GB RAM, 2 cores) - CI environment

## Advanced Deployment

### 1. High-Resource VM Templates

Create optimized VM configurations for your system:

```bash
# Create high-performance development VM
cat > tart/vm-configs/macos-dev-pro.yaml << 'EOF'
name: "macos-dev-pro"
base_image: "macos-sequoia"
description: "High-performance macOS development environment"

resources:
  memory: "16384"  # 16GB RAM
  disk: "120"      # 120GB disk
  cpu: "8"         # 8 CPU cores

settings:
  ssh_enabled: true
  vnc_enabled: true
  vnc_port: "5901"
  hardware_acceleration: true
  auto_start: true

post_setup:
  commands:
    - "echo 'Setting up high-performance development environment...'"
    - "# Install Xcode (full version)"
    - "# Install development tools suite"
    - "brew install git node python3 ruby golang rust"
    - "# Install iOS development tools"
    - "brew install fastlane xcbeautify ios-deploy"
    - "# Configure for performance"
    - "sudo sysctl -w vm.swappiness=10"
    - "# Setup development directories"
    - "mkdir -p ~/Development/{iOS,macOS,Flutter,React}"

network:
  mode: "bridged"
  port_forwards:
    - "2224:22"    # SSH
    - "5901:5901"  # VNC
    - "3000:3000"  # Dev server
    - "8080:8080"  # Alt dev server
    - "9229:9229"  # Node.js debug
EOF

# Create CI farm VM template
cat > tart/vm-configs/macos-ci-farm.yaml << 'EOF'
name: "macos-ci-farm"
base_image: "macos-sequoia"
description: "CI farm worker for parallel builds"

resources:
  memory: "8192"   # 8GB RAM
  disk: "80"       # 80GB disk
  cpu: "4"         # 4 CPU cores

settings:
  ssh_enabled: true
  vnc_enabled: false  # Headless for CI
  hardware_acceleration: true
  auto_start: true

post_setup:
  commands:
    - "echo 'Setting up CI farm worker...'"
    - "# Install Xcode command line tools"
    - "xcode-select --install"
    - "# Install CI tools"
    - "brew install fastlane xcbeautify carthage cocoapods"
    - "# Configure for headless CI"
    - "sudo systemsetup -setremotelogin on"
    - "sudo pmset -a displaysleep 0 sleep 0"
    - "# Setup CI workspace"
    - "mkdir -p ~/CI/{builds,artifacts,cache}"
    - "# Configure Git for CI"
    - "git config --global user.name 'CI Bot'"
    - "git config --global user.email 'ci@megalopolis.local'"

network:
  mode: "bridged"
  port_forwards:
    - "2225:22"    # SSH only
EOF
```

### 2. Deploy High-Resource VMs

```bash
# Create multiple development VMs
make vm-create VM_NAME=macos-dev-pro-1 VM_CONFIG=macos-dev-pro.yaml
make vm-create VM_NAME=macos-dev-pro-2 VM_CONFIG=macos-dev-pro.yaml

# Create CI farm workers
for i in {1..3}; do
  make vm-create VM_NAME=macos-ci-farm-$i VM_CONFIG=macos-ci-farm.yaml
done

# Create simulator farm
make vm-create VM_NAME=macos-simulator VM_CONFIG=macos-simulator.yaml
```

### 3. Scale Kind Cluster

Expand the Kubernetes cluster for more workloads:

```bash
# Edit kind configuration for more resources
cat > kind/config-scaled.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: homelab
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
- role: worker
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
EOF

# Recreate cluster with more nodes
make delete-cluster
KIND_CONFIG=kind/config-scaled.yaml make create-cluster
make bootstrap
```

## VM Automation

### 1. Automated VM Provisioning

Create a script for automated VM management:

```bash
cat > scripts/auto-provision-vms.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Automated VM provisioning for high-resource systems

# Configuration
declare -A VM_CONFIGS=(
    ["dev-primary"]="macos-dev-pro.yaml"
    ["dev-secondary"]="macos-dev-pro.yaml"
    ["ci-worker-1"]="macos-ci-farm.yaml"
    ["ci-worker-2"]="macos-ci-farm.yaml"
    ["ci-worker-3"]="macos-ci-farm.yaml"
    ["simulator-farm"]="macos-simulator.yaml"
)

# Resource limits
MAX_TOTAL_MEMORY=100000  # 100GB max for VMs
MAX_VMS=8

echo "🚀 Starting automated VM provisioning..."

# Check current resource usage
current_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | wc -l || echo 0)
echo "Current VMs: $current_vms"

if [ "$current_vms" -ge "$MAX_VMS" ]; then
    echo "⚠️  Maximum VM limit reached ($MAX_VMS)"
    exit 0
fi

# Provision VMs
for vm_name in "${!VM_CONFIGS[@]}"; do
    config_file="${VM_CONFIGS[$vm_name]}"
    
    echo "📦 Provisioning $vm_name with $config_file"
    
    if ./scripts/setup-vms.sh create "$vm_name" "$config_file"; then
        echo "✅ $vm_name created successfully"
        
        # Wait for VM to be ready
        echo "⏳ Waiting for $vm_name to boot..."
        sleep 30
        
        # Start VM
        ./scripts/setup-vms.sh start "$vm_name"
        echo "🟢 $vm_name is running"
    else
        echo "❌ Failed to create $vm_name"
    fi
    
    # Check if we've hit limits
    current_vms=$((current_vms + 1))
    if [ "$current_vms" -ge "$MAX_VMS" ]; then
        echo "⚠️  VM limit reached, stopping provisioning"
        break
    fi
done

echo "🎉 VM provisioning completed!"
./scripts/setup-vms.sh list
EOF

chmod +x scripts/auto-provision-vms.sh
```

### 2. VM Health Monitoring

```bash
cat > scripts/vm-health-monitor.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# VM health monitoring and auto-recovery

check_vm_health() {
    local vm_name="$1"
    
    echo "🔍 Checking health of $vm_name..."
    
    # Check if VM is running
    local status
    status=$(./tart-binary list 2>/dev/null | grep "^$vm_name" | awk '{print $2}' || echo "not_found")
    
    case "$status" in
        "running")
            echo "✅ $vm_name is running"
            
            # Check SSH connectivity
            local vm_ip
            vm_ip=$(./tart-binary ip "$vm_name" 2>/dev/null || echo "")
            
            if [ -n "$vm_ip" ]; then
                if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "admin@$vm_ip" "echo 'SSH OK'" 2>/dev/null; then
                    echo "✅ $vm_name SSH connectivity OK"
                    return 0
                else
                    echo "⚠️  $vm_name SSH connectivity failed"
                    return 1
                fi
            else
                echo "⚠️  $vm_name IP not available"
                return 1
            fi
            ;;
        "stopped")
            echo "🟡 $vm_name is stopped, attempting restart..."
            ./scripts/setup-vms.sh start "$vm_name"
            return 2
            ;;
        "not_found")
            echo "❌ $vm_name not found"
            return 3
            ;;
        *)
            echo "❓ $vm_name status unknown: $status"
            return 4
            ;;
    esac
}

# Monitor all VMs
echo "🏥 Starting VM health monitoring..."

while IFS= read -r vm_name; do
    [ -z "$vm_name" ] && continue
    check_vm_health "$vm_name" || echo "⚠️  Health check failed for $vm_name"
done < <(./tart-binary list 2>/dev/null | tail -n +2 | awk '{print $1}')

echo "✅ Health monitoring completed"
EOF

chmod +x scripts/vm-health-monitor.sh
```

## Monitoring & Status

### Enhanced Status Dashboard

```bash
cat > scripts/comprehensive-status.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Comprehensive system status dashboard

echo "═══════════════════════════════════════════════════════════════"
echo "🏠 MEGALOPOLIS HOMELAB STATUS DASHBOARD"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# System Resources
echo "💻 SYSTEM RESOURCES"
echo "───────────────────────────────────────────────────────────────"
echo "Host RAM: $(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)"GB"}')"
echo "Host CPU: $(sysctl -n hw.ncpu) cores"
echo "Load Average: $(uptime | awk -F'load averages:' '{print $2}')"
echo ""

# Kubernetes Cluster Status
echo "☸️  KUBERNETES CLUSTER"
echo "───────────────────────────────────────────────────────────────"
if ./kubectl cluster-info &>/dev/null; then
    echo "Status: 🟢 Running"
    echo "Nodes: $(./kubectl get nodes --no-headers | wc -l | tr -d ' ')"
    echo "Pods: $(./kubectl get pods -A --no-headers | wc -l | tr -d ' ') total"
    echo "Running: $(./kubectl get pods -A --no-headers | grep -c "Running")"
    echo "Pending: $(./kubectl get pods -A --no-headers | grep -c "Pending" || echo 0)"
    echo "Failed: $(./kubectl get pods -A --no-headers | grep -c -E "(Failed|Error)" || echo 0)"
    
    # Resource usage
    echo ""
    echo "Resource Usage:"
    ./kubectl top nodes 2>/dev/null || echo "  Metrics server not available"
else
    echo "Status: 🔴 Not Running"
fi
echo ""

# Virtual Machines Status
echo "🖥️  VIRTUAL MACHINES"
echo "───────────────────────────────────────────────────────────────"
if command -v ./tart-binary >/dev/null 2>&1 && ./tart-binary list >/dev/null 2>&1; then
    local total_vms running_vms stopped_vms
    total_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    running_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | grep -c "running" || echo 0)
    stopped_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | grep -c "stopped" || echo 0)
    
    echo "Total VMs: $total_vms"
    echo "Running: 🟢 $running_vms"
    echo "Stopped: 🔴 $stopped_vms"
    
    echo ""
    echo "VM Details:"
    ./tart-binary list 2>/dev/null | tail -n +2 | while read -r line; do
        vm_name=$(echo "$line" | awk '{print $1}')
        vm_status=$(echo "$line" | awk '{print $2}')
        
        case "$vm_status" in
            "running") status_icon="🟢" ;;
            "stopped") status_icon="🔴" ;;
            *) status_icon="🟡" ;;
        esac
        
        echo "  $status_icon $vm_name ($vm_status)"
    done
else
    echo "Status: ⚠️  Tart not available"
fi
echo ""

# Orchard Controller Status
echo "🌳 ORCHARD CONTROLLER"
echo "───────────────────────────────────────────────────────────────"
if ./kubectl get namespace orchard-system &>/dev/null; then
    local orchard_pods
    orchard_pods=$(./kubectl get pods -n orchard-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local running_pods
    running_pods=$(./kubectl get pods -n orchard-system --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    
    if [ "$orchard_pods" -gt 0 ]; then
        echo "Status: 🟢 Deployed ($running_pods/$orchard_pods pods running)"
        echo "Access: kubectl port-forward -n orchard-system svc/orchard-controller 8081:8080"
    else
        echo "Status: 🟡 Deployed but no pods"
    fi
else
    echo "Status: 🔴 Not deployed"
fi
echo ""

# Services Status
echo "🔧 CORE SERVICES"
echo "───────────────────────────────────────────────────────────────"

# ArgoCD
if ./kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -q "Running"; then
    echo "ArgoCD: 🟢 Running"
    echo "  Access: kubectl port-forward -n argocd svc/argocd-server 8080:443"
else
    echo "ArgoCD: 🔴 Not Running"
fi

# Add more services as needed
echo ""

# Quick Actions
echo "⚡ QUICK ACTIONS"
echo "───────────────────────────────────────────────────────────────"
echo "make status          - Refresh this status"
echo "make validate        - Run health checks"
echo "make vm-health       - Check VM health"
echo "make scale-up        - Add more VMs"
echo "make scale-down      - Remove idle VMs"
echo ""

echo "Last updated: $(date)"
echo "═══════════════════════════════════════════════════════════════"
EOF

chmod +x scripts/comprehensive-status.sh
```

### Add Comprehensive Status to Makefile

```bash
cat >> Makefile << 'EOF'

# Enhanced monitoring and automation
comprehensive-status: ## Show detailed system status dashboard
	./scripts/comprehensive-status.sh

vm-health: ## Check and repair VM health
	./scripts/vm-health-monitor.sh

auto-provision: ## Automatically provision VMs based on resource availability
	./scripts/auto-provision-vms.sh

scale-up: ## Scale up VMs and cluster based on available resources
	@echo "Scaling up Megalopolis infrastructure..."
	@./scripts/auto-provision-vms.sh
	@echo "Scale-up completed!"

scale-down: ## Scale down idle VMs to free resources
	@echo "Scaling down idle VMs..."
	@./scripts/setup-vms.sh list | grep "stopped" | awk '{print $$1}' | head -3 | xargs -I {} ./scripts/setup-vms.sh delete {} || true
	@echo "Scale-down completed!"

monitoring: ## Start continuous monitoring (runs in background)
	@echo "Starting continuous monitoring..."
	@while true; do \
		./scripts/comprehensive-status.sh > /tmp/megalopolis-status.log; \
		./scripts/vm-health-monitor.sh >> /tmp/megalopolis-health.log; \
		sleep 300; \
	done &
	@echo "Monitoring started in background. Logs: /tmp/megalopolis-*.log"

deploy-full: ## Full deployment for high-resource systems
	@echo "🚀 Starting full high-resource deployment..."
	make ensure-tools
	make create-cluster
	make bootstrap
	make auto-provision
	make comprehensive-status
	@echo "🎉 Full deployment completed!"
EOF
```

## Production Workflows

### 1. iOS App CI/CD Pipeline

```bash
cat > workflows/ios-ci-pipeline.yaml << 'EOF'
# iOS CI/CD Pipeline Configuration
name: iOS Build Pipeline
description: Automated iOS app building using VM farm

# VM Pool Configuration
vm_pool:
  - name: "ios-build-1"
    config: "macos-ci-farm.yaml"
    capabilities: ["xcode", "fastlane", "ios-sim"]
  - name: "ios-build-2" 
    config: "macos-ci-farm.yaml"
    capabilities: ["xcode", "fastlane", "ios-sim"]

# Pipeline Stages
stages:
  - name: "setup"
    vm: "any"
    commands:
      - "git clone $REPO_URL ~/build"
      - "cd ~/build && bundle install"
      
  - name: "test"
    vm: "ios-build-1"
    parallel: true
    commands:
      - "cd ~/build && fastlane test"
      - "cd ~/build && fastlane ui_test"
      
  - name: "build"
    vm: "ios-build-2"
    commands:
      - "cd ~/build && fastlane build_release"
      
  - name: "archive"
    vm: "any"
    commands:
      - "cd ~/build && fastlane archive_and_upload"
EOF
```

### 2. Development Environment Setup

```bash
cat > workflows/dev-environment-setup.sh << 'EOF'
#!/bin/bash
# Automated development environment provisioning

# Create development team VMs
for dev in alice bob charlie; do
    echo "Setting up development environment for $dev..."
    
    # Create personalized VM
    make vm-create VM_NAME="dev-${dev}" VM_CONFIG=macos-dev-pro.yaml
    
    # Wait for VM to be ready
    sleep 60
    
    # Setup development tools
    vm_ip=$(./tart-binary ip "dev-${dev}")
    ssh admin@$vm_ip "
        # Install developer-specific tools
        brew install --cask visual-studio-code xcode
        
        # Setup git configuration
        git config --global user.name '$dev'
        git config --global user.email '${dev}@company.com'
        
        # Clone common repositories
        mkdir -p ~/Development
        cd ~/Development
        # git clone https://github.com/company/main-app.git
        # git clone https://github.com/company/shared-lib.git
        
        echo 'Development environment ready for $dev!'
    "
done
EOF

chmod +x workflows/dev-environment-setup.sh
```

## Scaling Strategies

### 1. Resource-Based Auto-Scaling

Monitor system resources and automatically scale VMs:

```bash
cat > scripts/auto-scale.sh << 'EOF'
#!/bin/bash
# Intelligent auto-scaling based on resource usage

# Get current resource usage
memory_usage=$(vm_stat | awk '/free/ {free=$3} /inactive/ {inactive=$5} END {print 100-((free+inactive)*4096/1024/1024/1024)*100/128}')
cpu_usage=$(top -l 1 | awk '/CPU usage/ {print $3}' | sed 's/%//')

echo "Current usage - Memory: ${memory_usage}%, CPU: ${cpu_usage}%"

# Scale up if usage is low and we have capacity
if (( $(echo "$memory_usage < 70" | bc -l) )) && (( $(echo "$cpu_usage < 60" | bc -l) )); then
    echo "Resources available, considering scale-up..."
    ./scripts/auto-provision-vms.sh
fi

# Scale down if usage is very low
if (( $(echo "$memory_usage < 40" | bc -l) )) && (( $(echo "$cpu_usage < 30" | bc -l) )); then
    echo "Low resource usage, considering scale-down..."
    make scale-down
fi
EOF

chmod +x scripts/auto-scale.sh
```

### 2. Workload-Based Scaling

Scale based on actual workload demands:

```bash
cat > scripts/workload-scale.sh << 'EOF'
#!/bin/bash
# Scale VMs based on workload queue

# Check CI queue length (example with GitHub Actions)
queue_length=$(gh api repos/owner/repo/actions/runs --jq '.workflow_runs | map(select(.status == "queued")) | length')

# Scale CI VMs based on queue
if [ "$queue_length" -gt 5 ]; then
    echo "High CI queue ($queue_length), scaling up..."
    for i in {1..2}; do
        make vm-create VM_NAME="ci-surge-$i" VM_CONFIG=macos-ci-farm.yaml
    done
elif [ "$queue_length" -eq 0 ]; then
    echo "Empty CI queue, scaling down surge VMs..."
    ./tart-binary list | grep "ci-surge" | awk '{print $1}' | xargs -I {} ./scripts/setup-vms.sh delete {}
fi
EOF

chmod +x scripts/workload-scale.sh
```

This comprehensive documentation provides everything needed to fully utilize your 128GB, multi-core system with Megalopolis. The automation scripts will help manage the VMs efficiently while the monitoring provides visibility into the entire stack.

Would you like me to add any specific sections or dive deeper into particular workflows?