#!/bin/bash
set -euo pipefail

# Use project-local binaries
KUBECTL="./kubectl"

echo "Starting homelab bootstrap..."

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
$KUBECTL wait --for=condition=Ready nodes --all --timeout=300s

# Create namespaces
echo "Creating namespaces..."
$KUBECTL create namespace argocd --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace cert-manager --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace ingress-nginx --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace external-secrets --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace monitoring --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace keycloak --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace orchard-system --dry-run=client -o yaml | $KUBECTL apply -f -

# Install ArgoCD
echo "Installing ArgoCD..."
$KUBECTL apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
$KUBECTL wait --for=condition=Ready pods -n argocd -l app.kubernetes.io/name=argocd-server --timeout=300s

# Get ArgoCD password
echo "ArgoCD admin password:"
$KUBECTL -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# Deploy Orchard infrastructure
echo "Deploying Orchard VM management infrastructure..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
K8S_MANIFESTS_DIR="$PROJECT_DIR/k8s-manifests"

if [[ -d "$K8S_MANIFESTS_DIR" ]]; then
    echo "Applying Orchard manifests..."
    $KUBECTL apply -f "$K8S_MANIFESTS_DIR/orchard-namespace.yaml"
    $KUBECTL apply -f "$K8S_MANIFESTS_DIR/orchard-rbac.yaml"
    $KUBECTL apply -f "$K8S_MANIFESTS_DIR/orchard-pvc.yaml"
    $KUBECTL apply -f "$K8S_MANIFESTS_DIR/orchard-deployment.yaml"
    $KUBECTL apply -f "$K8S_MANIFESTS_DIR/orchard-service.yaml"
    $KUBECTL apply -f "$K8S_MANIFESTS_DIR/vm-api-bridge.yaml"
    
    echo "Waiting for Orchard controller to be ready..."
    $KUBECTL wait --for=condition=Ready pods -n orchard-system -l app=orchard-controller --timeout=300s || {
        echo "WARNING: Orchard controller may not be ready. This is normal if Orchard image is not available."
        echo "VM management features will be limited to direct Tart integration."
    }
    
    echo "Orchard infrastructure deployed successfully!"
else
    echo "WARNING: Orchard manifests directory not found. Skipping Orchard deployment."
fi

echo "Bootstrap complete!"
echo ""
echo "Access Information:"
echo "==================="
echo "ArgoCD:"
echo "  $KUBECTL port-forward -n argocd svc/argocd-server 8080:443"
echo "  Open https://localhost:8080"
echo "  Username: admin"
echo ""
echo "Orchard Controller (if deployed):"
echo "  $KUBECTL port-forward -n orchard-system svc/orchard-controller 8081:8080"
echo "  Open http://localhost:8081"
echo ""
echo "VM Management:"
echo "  make vms           - List all VMs"
echo "  make vm-status     - Show VM status"
echo "  make vm-create     - Create new VM"