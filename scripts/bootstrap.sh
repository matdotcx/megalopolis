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

# Deploy VM management infrastructure
echo "Deploying VM management infrastructure..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
K8S_MANIFESTS_DIR="$PROJECT_DIR/k8s-manifests"

if [[ -d "$K8S_MANIFESTS_DIR" ]]; then
    echo "Applying VM operator manifests..."
    
    # Deploy the minimal VM operator
    [[ -f "$K8S_MANIFESTS_DIR/vm-operator-deployment.yaml" ]] && $KUBECTL apply -f "$K8S_MANIFESTS_DIR/vm-operator-deployment.yaml"
    [[ -f "$K8S_MANIFESTS_DIR/vm-operator-service.yaml" ]] && $KUBECTL apply -f "$K8S_MANIFESTS_DIR/vm-operator-service.yaml"
    
    echo "VM management available via:"
    echo "- HTTP API: kubectl port-forward -n orchard-system svc/vm-operator 8082:8082"
    echo "- CLI scripts: scripts/setup-vms.sh"
    
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
echo "VM Operator API:"
echo "  $KUBECTL port-forward -n orchard-system svc/vm-operator 8082:8082"
echo "  Open http://localhost:8082/health"
echo "  API endpoints: /vms, /vms/{name}, /vms/{name}/start, /vms/{name}/stop"
echo ""
echo "VM Management (CLI):"
echo "  make vms                    - List all VMs"
echo "  scripts/setup-vms.sh list  - List VMs with details"
echo "  scripts/setup-vms.sh health <vm> - Check VM health"
echo "  scripts/setup-vms.sh wait <vm>   - Wait for VM readiness"
echo "  scripts/setup-vms.sh help  - Show all VM management commands"