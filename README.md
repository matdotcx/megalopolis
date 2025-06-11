# Homelab on macOS

A fully automated Kubernetes homelab setup for macOS using Kind (Kubernetes in Docker).

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd homelab

# Set up everything automatically (installs Colima if needed, starts Docker)
make init

# Validate the installation
make validate
```

## Available Commands

- `make help` - Show all available commands
- `make init` - Initialize the homelab (downloads tools, creates cluster, installs ArgoCD)
- `make status` - Check cluster status
- `make validate` - Validate cluster health
- `make rebuild` - Tear down and rebuild everything
- `make clean` - Remove cluster and clean up
- `make test-automation` - Test the full automation cycle with timing

## Architecture

- **Kubernetes**: Kind cluster with 4 nodes (1 control-plane, 3 workers)
- **Container Runtime**: Colima or Docker Desktop (automatic detection)
- **GitOps**: ArgoCD for continuous deployment
- **Tools**: kubectl v1.33.1, helm v3.18.2, kind v0.23.0

## Accessing ArgoCD

After running `make init`:

```bash
# Port forward to ArgoCD
./kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get admin password
./kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI at https://localhost:8080
# Username: admin
```

## Project Structure

```
homelab/
├── Makefile              # Automation commands
├── scripts/              # Automation scripts
│   ├── bootstrap.sh      # ArgoCD installation
│   ├── ensure-tools.sh   # Tool management
│   └── validate-cluster.sh # Health checks
├── kind/                 # Cluster configuration
├── clusters/             # GitOps manifests
└── kubectl, helm, kind-binary # Local tools
```

## Container Runtime

The homelab automatically detects and uses your preferred container runtime:

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

## Troubleshooting

### Container Runtime Issues
- **Docker not accessible**: Run `./scripts/check-docker.sh` to diagnose
- **Colima installation**: Run `./scripts/setup-colima.sh` to install via MacPorts
- **Resource issues**: Colima is configured with 4 CPU, 8GB RAM, 60GB disk
