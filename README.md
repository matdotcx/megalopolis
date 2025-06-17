# Megalopolis - Unified Homelab on macOS

A fully automated homelab orchestration system combining Kubernetes containers (via Kind) and native macOS virtual machines (via Tart) for comprehensive development and CI/CD environments.

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd megalopolis

# Set up everything automatically (Kubernetes cluster + macOS VMs)
make init

# Check status of cluster and VMs
make status

# Validate the installation
make validate
```

## Available Commands

### Core Commands
- `make help` - Show all available commands
- `make init` - Initialize the homelab (downloads tools, creates cluster, sets up VMs)
- `make status` - Check cluster and VM status
- `make validate` - Validate cluster and VM health
- `make rebuild` - Tear down and rebuild everything
- `make clean` - Remove cluster, VMs, and clean up
- `make test-automation` - Test the full automation cycle with timing

### Status Dashboard 🏙️
- `make dashboard` - Launch web status dashboard (manual)
- Automatically launched after `make init` and `make deploy-full`
- Visit http://localhost:8090 for real-time infrastructure monitoring
- Shows ✅/⚠️/❌ status for all services with auto-refresh

### VM Management
- `make vms` - List all virtual machines
- `make vm-create VM_NAME=name VM_CONFIG=config.yaml` - Create new VM from template
- `make vm-connect VM_NAME=name` - Connect to a VM via SSH
- `make vm-rebuild` - Rebuild all VMs from base images

## Architecture

### Unified Homelab Environment
```
M3 Mac Host
├── Kind Cluster (Linux containers)
│   ├── ArgoCD, cert-manager, ingress-nginx
│   ├── Orchard controller (VM management)
│   └── Applications and services
├── Tart VMs (Native macOS/Linux VMs)
│   ├── macos-dev (Development environment)
│   ├── macos-ci (CI/CD environment)
│   └── Custom VMs as needed
```

### Components
- **Kubernetes**: Kind cluster with 4 nodes (1 control-plane, 3 workers)
- **Container Runtime**: Colima or Docker Desktop (automatic detection)
- **Virtual Machines**: Tart for native macOS and Linux VMs
- **VM Management**: Orchard controller for unified VM orchestration
- **GitOps**: ArgoCD for continuous deployment
- **Tools**: kubectl v1.33.1, helm v3.18.2, kind v0.23.0, tart (latest)

## Accessing Services

### ArgoCD (GitOps Dashboard)
After running `make init`:

```bash
# Port forward to ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI at https://localhost:8080
# Username: admin
```

### Orchard Controller (VM Management)
```bash
# Port forward to Orchard
kubectl port-forward -n orchard-system svc/orchard-controller 8081:8080

# Access VM management UI at http://localhost:8081
```

### Virtual Machines
```bash
# Connect to development VM
make vm-connect VM_NAME=macos-dev

# Or use SSH directly
ssh -p 2222 admin@localhost  # macos-dev
ssh -p 2223 admin@localhost  # macos-ci
```

## Project Structure

```
megalopolis/
├── Makefile              # Automation commands
├── scripts/              # Automation scripts
│   ├── bootstrap.sh      # ArgoCD installation
│   ├── ensure-tools.sh   # Tool management
│   ├── setup-vms.sh      # VM lifecycle management
│   ├── auto-provision-vms.sh # Automated VM provisioning
│   └── validate-cluster.sh # Health checks
├── kind/                 # Kubernetes cluster configuration
├── tart/                 # VM configurations and templates
│   ├── base-images.yaml  # VM base image definitions
│   ├── orchard-config.yaml # Orchard controller config
│   └── vm-configs/       # Individual VM templates
├── k8s-manifests/        # Kubernetes manifests
└── get_helm.sh          # Helm installation script
```

## Virtual Machine Support

Megalopolis includes native macOS and Linux VM support via Tart, providing isolated environments for development and CI/CD.

### VM Templates
- **macos-dev**: Development environment with 6GB RAM, GUI access, development tools
- **macos-ci**: CI environment with 4GB RAM, headless operation, CI tools
- **macos-dev-pro**: High-resource development with 8GB RAM for intensive workloads
- **macos-ci-farm**: Multi-instance CI environment for parallel builds
- **macos-simulator-farm**: iOS simulator testing environment

### VM Management
```bash
# List available VMs
make vms

# Create new VM from template
make vm-create VM_NAME=my-dev VM_CONFIG=macos-dev.yaml

# Start/stop VMs
./scripts/setup-vms.sh start macos-dev
./scripts/setup-vms.sh stop macos-dev

# Connect to VM
make vm-connect VM_NAME=macos-dev
```

## Container Runtime

The system automatically detects and uses your preferred container runtime:

### Colima (Recommended for macOS)
Colima is a lightweight Docker alternative that uses fewer resources than Docker Desktop.

```bash
# Install Colima via MacPorts (automated by setup script)
./scripts/setup-colima.sh

# Manual Colima commands (if needed)
colima start --cpu 4 --memory 8 --disk 60
colima status
colima stop
```

### Docker Desktop
Falls back to Docker Desktop if Colima is not available.

## System Requirements

### Minimum Requirements
- **CPU**: Apple Silicon M1/M2/M3 Mac
- **RAM**: 16GB (8GB for host + 4GB per VM minimum)
- **Disk**: 200GB+ free space
- **macOS**: Big Sur 11.0+ (for Tart support)

### Recommended Configuration
- **RAM**: 32GB+ for multiple VMs and containers
- **Disk**: 500GB+ SSD for optimal performance
- **CPU**: M2 Pro/Max or M3 for best performance

## Troubleshooting

### Container Runtime Issues
- **Docker not accessible**: Run `./scripts/check-docker.sh` to diagnose
- **Colima installation**: Run `./scripts/setup-colima.sh` to install via MacPorts
- **Resource issues**: Colima is configured with 4 CPU, 8GB RAM, 60GB disk

### VM Issues
- **Tart not found**: Run `make ensure-tools` to install Tart automatically
- **VM creation fails**: Check disk space and ensure base images are available
- **Performance issues**: Reduce VM memory allocation or limit concurrent VMs
- **SSH connection fails**: Verify VM is running and ports are not conflicted

For detailed VM documentation, see [tart/README.md](tart/README.md).
