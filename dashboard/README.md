# Megalopolis Status Dashboard

A simple web-based dashboard that shows the real-time status of all Megalopolis infrastructure components.

## Features

- 🏙️ **Real-time Status**: Shows health of all services with ✅/❌/⚠️ indicators
- 🔄 **Auto-refresh**: Updates every 30 seconds automatically
- 📱 **Responsive Design**: Works on desktop and mobile
- 🎨 **Clean UI**: Modern, easy-to-read interface
- 📊 **Summary Stats**: Overall system health overview

## Quick Start

### Option 1: Using Make (Recommended)
```bash
# Start dashboard (foreground)
make dashboard

# Start dashboard in background
make dashboard-bg
```

### Option 2: Direct Python
```bash
# Start on default port 8090
python3 dashboard/server.py

# Start on custom port
python3 dashboard/server.py 8080
```

### Option 3: Just the API
```bash
# Get JSON status data
./dashboard/status-api.sh
```

## Dashboard URL

Once started, open your browser to:
**http://localhost:8090**

## Components Monitored

### 🐳 Infrastructure
- **Docker**: Container runtime
- **Kind Cluster**: Kubernetes cluster
- **kubectl**: Kubernetes client  
- **Tart**: VM management

### ☸️ Kubernetes Services
- **ArgoCD**: GitOps platform
- **Orchard Controller**: VM orchestration
- **Cert Manager**: TLS certificates
- **Ingress Nginx**: HTTP routing

### 🖥️ Virtual Machines
- **macOS Dev**: Development environment
- **macOS CI**: Build environment
- **VM Count**: Total running VMs

### 🔧 Support Services
- **External Secrets**: Secret management
- **Monitoring**: Observability stack
- **Keycloak**: Identity provider
- **Network**: Docker networking

## Status Indicators

- ✅ **Healthy**: Service is running correctly
- ⚠️ **Warning**: Service exists but may not be fully operational
- ❌ **Unhealthy**: Service is down or not configured

## API Endpoint

The dashboard exposes a JSON API at `/api/status`:

```bash
curl http://localhost:8090/api/status
```

Example response:
```json
{
  "timestamp": "2025-06-17T13:50:44Z",
  "services": {
    "docker": {"status": "healthy", "details": "Container runtime"},
    "argocd": {"status": "healthy", "details": "7 pods running"},
    "macos-dev": {"status": "warning", "details": "Stopped"}
  },
  "summary": {
    "healthy": 8,
    "warning": 4,
    "unhealthy": 3
  }
}
```

## Files

- `index.html` - Main dashboard interface
- `server.py` - Python HTTP server
- `status-api.sh` - Backend script that checks service status
- `README.md` - This documentation

## Troubleshooting

### Port Already in Use
```bash
# Try a different port
python3 dashboard/server.py 8091
```

### Permission Errors
```bash
# Make scripts executable
chmod +x dashboard/status-api.sh dashboard/server.py
```

### Status Check Issues
The dashboard relies on the same tools as the test suite:
- Ensure `kubectl`, `tart-binary`, and `kind-binary` are in the project root
- Verify Kubernetes cluster is accessible
- Check that Docker is running

## Integration

The dashboard integrates with the existing Megalopolis infrastructure:
- Uses the same validation logic as the test suite
- Monitors the same services defined in the Makefile
- Provides visual feedback for `make status` equivalent information