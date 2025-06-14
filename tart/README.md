# Tart VM Integration

This directory contains configuration files for Tart virtual machine integration with Megalopolis.

## Overview

Megalopolis now supports both Kubernetes containers (via Kind) and macOS virtual machines (via Tart), providing a unified homelab environment for development and CI/CD.

## Architecture

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

## Files

- `base-images.yaml` - Defines available base images for VM creation
- `orchard-config.yaml` - Configuration for the Orchard controller
- `vm-configs/` - Individual VM configuration files
  - `macos-dev.yaml` - Development VM with 6GB RAM, GUI access
  - `macos-ci.yaml` - CI VM with 4GB RAM, headless operation

## Prerequisites

1. **Tart Installation** (via GitHub releases):
   ```bash
   curl -LO https://github.com/cirruslabs/tart/releases/latest/download/tart.tar.gz && tar -xzf tart.tar.gz && sudo mv tart.app /Applications/ && sudo ln -sf /Applications/tart.app/Contents/MacOS/tart /usr/local/bin/tart && rm tart.tar.gz
   ```
   
   Or let Megalopolis install it automatically:
   ```bash
   make ensure-tools
   ```

2. **Base Images**: 
   The system will automatically pull base images from:
   - `ghcr.io/cirruslabs/macos-sequoia:latest` for macOS VMs
   - `ghcr.io/cirruslabs/ubuntu:jammy` for Linux VMs

## Usage

### Basic Commands

```bash
# Initialize everything (Kind + VMs)
make init

# Check status of both cluster and VMs
make status

# List all VMs
make vms

# Create a new VM from template
make vm-create VM_NAME=my-vm VM_CONFIG=macos-dev.yaml

# Connect to a VM
make vm-connect VM_NAME=macos-dev

# Rebuild all VMs from base images
make vm-rebuild

# Clean up everything
make clean
```

### Direct VM Management

```bash
# Setup VMs directly
./scripts/setup-vms.sh setup

# List VMs
./scripts/setup-vms.sh list

# Create specific VM
./scripts/setup-vms.sh create my-vm macos-dev.yaml

# Start/stop VMs
./scripts/setup-vms.sh start macos-dev
./scripts/setup-vms.sh stop macos-dev
```

## VM Configurations

### Development VM (macos-dev)
- **Resources**: 6GB RAM, 60GB disk, 4 CPU cores
- **Features**: SSH, VNC, hardware acceleration
- **Ports**: 2222 (SSH), 5900 (VNC), 3000/8080 (dev servers)
- **Tools**: Xcode CLI tools, Homebrew, development tools

### CI VM (macos-ci)
- **Resources**: 4GB RAM, 40GB disk, 2 CPU cores
- **Features**: SSH only, auto-start, headless
- **Ports**: 2223 (SSH)
- **Tools**: Xcode CLI tools, Fastlane, CI tools

## Orchard Integration

The Orchard controller runs inside the Kind cluster and provides:

- REST API for VM management
- Integration with Kubernetes workflows
- VM lifecycle automation
- Resource monitoring

Access the Orchard controller:
```bash
kubectl port-forward -n orchard-system svc/orchard-controller 8081:8080
open http://localhost:8081
```

## Customization

### Creating Custom VM Configs

1. Copy an existing config from `vm-configs/`
2. Modify resources, ports, and post-setup commands
3. Use with `make vm-create VM_CONFIG=your-config.yaml`

### Adding Base Images

Edit `base-images.yaml` to add new base images:

```yaml
base_images:
  my-custom-image:
    source: "ghcr.io/my-org/my-image:latest"
    description: "My custom image"
    arch: "arm64"
    recommended_memory: "4096"
    recommended_disk: "40"
```

## Troubleshooting

### Tart Not Available
If tart commands fail, ensure it's installed:
```bash
# Via MacPorts
sudo port install tart

# Verify installation
tart --version

# Rerun tool setup
make ensure-tools
```

### VM Creation Fails
- Check base image availability
- Ensure sufficient disk space (VMs can be 40-60GB each)
- Verify VM name doesn't conflict with existing VMs

### Performance Issues
- Reduce VM memory allocation in config files
- Limit number of concurrent VMs
- Ensure host has sufficient resources (recommend 16GB+ RAM for multiple VMs)

## Resource Requirements

### Minimum Host Requirements
- **CPU**: Apple Silicon M1/M2/M3 Mac
- **RAM**: 16GB (8GB for host + 4GB per VM minimum)
- **Disk**: 200GB+ free space
- **macOS**: Big Sur 11.0+ (for Tart support)

### Recommended Configuration
- **RAM**: 32GB+ for multiple VMs
- **Disk**: 500GB+ SSD for good performance
- **CPU**: M2 Pro/Max or M3 for optimal performance