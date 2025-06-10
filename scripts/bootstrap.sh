#\!/bin/bash
set -euo pipefail

echo "🚀 Starting homelab bootstrap..."

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Create namespaces
echo "📁 Creating namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "🔄 Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Ready pods -n argocd -l app.kubernetes.io/name=argocd-server --timeout=300s

# Get ArgoCD password
echo "🔐 ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

echo "✅ Bootstrap complete\!"
echo ""
echo "To access ArgoCD:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  Open https://localhost:8080"
echo "  Username: admin"
EOF && chmod +x scripts/bootstrap.sh