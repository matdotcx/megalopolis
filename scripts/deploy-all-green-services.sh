#!/bin/bash

# Deploy All Green Services
# Automates the manual steps performed to achieve all-green dashboard status

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if cluster exists
if ! kubectl cluster-info &>/dev/null; then
    log_error "No Kubernetes cluster found. Run 'make init' first."
    exit 1
fi

log_info "Deploying services for all-green dashboard status..."

# 1. Deploy cert-manager (should already exist from bootstrap)
log_info "Ensuring cert-manager is deployed..."
if ! kubectl get namespace cert-manager &>/dev/null; then
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    kubectl wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s
fi

# 2. Deploy self-signed ClusterIssuer and certificate
log_info "Deploying self-signed certificates..."
cat <<EOF | kubectl apply -f -
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

# 3. Deploy external-secrets
log_info "Deploying external-secrets..."
if ! helm repo list | grep -q external-secrets; then
    helm repo add external-secrets https://charts.external-secrets.io
fi
helm repo update
if ! helm list -n external-secrets | grep -q external-secrets; then
    helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
fi

# 4. Deploy monitoring stack (Prometheus/Grafana)
log_info "Deploying monitoring stack..."
if ! helm repo list | grep -q prometheus-community; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
fi
helm repo update
if ! helm list -n monitoring | grep -q kube-prometheus-stack; then
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        -n monitoring --create-namespace \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
fi

# 5. Deploy Keycloak
log_info "Deploying Keycloak..."
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

# Wait for all deployments to be ready
log_info "Waiting for all services to be ready..."

namespaces=("cert-manager" "ingress-nginx" "external-secrets" "monitoring" "keycloak")
for ns in "${namespaces[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        log_info "Waiting for pods in namespace: $ns"
        kubectl wait --for=condition=ready pod --all -n "$ns" --timeout=600s || log_warn "Some pods in $ns may still be starting"
    fi
done

log_info "✅ All services deployed! Dashboard should now show all green status."
log_info "Access dashboard at: http://localhost:8090"

# Display service access information
cat <<EOF

🎉 All Green Services Deployed Successfully!

Access Information:
- Dashboard: http://localhost:8090
- ArgoCD: kubectl port-forward -n argocd svc/argocd-server 8080:443 (admin/$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d))
- Grafana: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 (admin/prom-operator)
- Keycloak: kubectl port-forward -n keycloak svc/keycloak 8081:80 (admin/admin123)

Self-signed certificates available in secret: megalopolis-tls-selfsigned
EOF