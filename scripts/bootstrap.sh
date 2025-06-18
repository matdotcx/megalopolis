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

# Install ingress-nginx
echo "Installing ingress-nginx..."
# Label control plane node for ingress
$KUBECTL label node homelab-control-plane ingress-ready=true --overwrite

# Deploy ingress-nginx
$KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/kind/deploy.yaml

# Wait for ingress-nginx to be ready
echo "Waiting for ingress-nginx to be ready..."
$KUBECTL wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

echo "✅ ingress-nginx deployed successfully"

# Deploy core services for complete homelab setup
echo "Deploying core services..."

# Deploy external-secrets
echo "Deploying external-secrets..."
if ! helm repo list | grep -q external-secrets; then
    helm repo add external-secrets https://charts.external-secrets.io
fi
helm repo update
if ! helm list -n external-secrets | grep -q external-secrets; then
    helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
fi

# Deploy monitoring stack (Prometheus/Grafana)
echo "Deploying monitoring stack..."
if ! helm repo list | grep -q prometheus-community; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
fi
helm repo update
if ! helm list -n monitoring | grep -q kube-prometheus-stack; then
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        -n monitoring --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
fi

# Deploy Keycloak
echo "Deploying Keycloak..."
if ! helm repo list | grep -q bitnami; then
    helm repo add bitnami https://charts.bitnami.com/bitnami
fi
helm repo update
if ! helm list -n keycloak | grep -q keycloak; then
    helm install keycloak bitnami/keycloak \
        -n keycloak --create-namespace \
        --set auth.adminUser=admin \
        --set auth.adminPassword=admin123 \
        --set postgresql.enabled=true
fi

# Deploy self-signed certificates
echo "Deploying self-signed certificates..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: megalopolis-selfsigned-cert
  namespace: default
spec:
  commonName: megalopolis.iaconelli.org
  dnsNames:
  - megalopolis.iaconelli.org
  - localhost
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  secretName: megalopolis-tls-selfsigned
EOF

echo "✅ Core services deployed successfully"

# Deploy Let's Encrypt DNS-01 support
echo "Setting up Let's Encrypt DNS-01 with NS1..."
if ! helm repo list | grep -q cert-manager-webhook-ns1; then
    helm repo add cert-manager-webhook-ns1 https://ns1.github.io/cert-manager-webhook-ns1
fi
helm repo update
if ! helm list -n cert-manager | grep -q cert-manager-webhook-ns1; then
    helm install cert-manager-webhook-ns1 cert-manager-webhook-ns1/cert-manager-webhook-ns1 --namespace cert-manager
fi

# Create NS1 API credentials if provided
if [ -n "$NS1_API_KEY" ]; then
    echo "Setting up NS1 API credentials for Let's Encrypt DNS-01..."
    kubectl create secret generic ns1-credentials \
        --from-literal=apiKey="$NS1_API_KEY" \
        -n cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply DNS-01 ClusterIssuers
    kubectl apply -f "$PROJECT_DIR/k8s-manifests/letsencrypt-dns01-issuer.yaml"
    echo "✅ Let's Encrypt DNS-01 configured"
else
    echo "⚠️  NS1_API_KEY not provided - skipping Let's Encrypt DNS-01 setup"
    echo "   To enable: export NS1_API_KEY=your_api_key"
fi

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
echo "Dashboard:"
echo "  make dashboard              - Launch web status dashboard"
echo ""
echo "ArgoCD:"
echo "  $KUBECTL port-forward -n argocd svc/argocd-server 8080:443"
echo "  Open https://localhost:8080"
echo "  Username: admin"
echo ""
echo "Grafana:"
echo "  $KUBECTL port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  Open http://localhost:3000"
echo "  Username: admin, Password: prom-operator"
echo ""
echo "Keycloak:"
echo "  $KUBECTL port-forward -n keycloak svc/keycloak 8081:80"
echo "  Open http://localhost:8081"
echo "  Username: admin, Password: admin123"
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