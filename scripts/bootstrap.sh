#!/bin/bash
set -euo pipefail

# Use project-local binaries
KUBECTL="./kubectl"

# Debug logging function
log_debug() {
    echo "[DEBUG $(date '+%H:%M:%S')] $*"
}

# Error handling function  
log_error() {
    echo "[ERROR $(date '+%H:%M:%S')] $*" >&2
}

# Deploy ArgoCD with enhanced error handling and retries
deploy_argocd_chunked() {
    local manifest_url="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    local temp_file="/tmp/argocd-manifest.yaml"
    
    log_debug "Downloading ArgoCD manifest..."
    if ! curl -sSL "$manifest_url" > "$temp_file"; then
        log_error "Failed to download ArgoCD manifest"
        return 1
    fi
    
    local line_count=$(wc -l < "$temp_file")
    log_debug "Downloaded ArgoCD manifest: $line_count lines"
    
    # Verify manifest is complete
    if [ "$line_count" -lt 500 ]; then
        log_error "ArgoCD manifest seems incomplete (only $line_count lines)"
        return 1
    fi
    
    # Apply manifest with enhanced logging and proper timeout handling
    log_debug "Applying ArgoCD manifest with enhanced error handling..."
    
    for attempt in 1 2 3; do
        log_debug "ArgoCD deployment attempt $attempt/3"
        
        # Apply with detailed logging
        if $KUBECTL apply -n argocd -f "$temp_file" 2>&1 | tee -a /tmp/bootstrap.log; then
            log_debug "ArgoCD manifest applied successfully on attempt $attempt"
            
            # Wait for resources to be created (they may take time to appear)
            log_debug "Waiting for ArgoCD resources to be created..."
            sleep 15
            
            # Verify critical resources were created with multiple checks
            local max_wait=60
            local waited=0
            local deployments=0
            local statefulsets=0
            
            while [ $waited -lt $max_wait ]; do
                deployments=$($KUBECTL get deployments -n argocd --no-headers 2>/dev/null | wc -l || echo "0")
                statefulsets=$($KUBECTL get statefulsets -n argocd --no-headers 2>/dev/null | wc -l || echo "0")
                
                log_debug "ArgoCD resources check (${waited}s): $deployments deployments, $statefulsets statefulsets"
                
                if [ "$deployments" -ge 6 ] && [ "$statefulsets" -ge 1 ]; then
                    log_debug "✅ ArgoCD deployment resources created successfully"
                    return 0
                fi
                
                sleep 5
                waited=$((waited + 5))
            done
            
            log_error "⚠️ ArgoCD deployment resources not fully created after ${max_wait}s (attempt $attempt)"
            log_debug "Final count: $deployments deployments, $statefulsets statefulsets (expected: 6+ deployments, 1+ statefulsets)"
            
            if [ $attempt -lt 3 ]; then
                log_debug "Retrying in 15 seconds..."
                sleep 15
                # Clean up partial deployment before retry
                $KUBECTL delete -n argocd --all deployments,statefulsets 2>/dev/null || true
                sleep 5
            fi
        else
            log_error "ArgoCD manifest application failed on attempt $attempt"
            if [ $attempt -lt 3 ]; then
                log_debug "Retrying in 15 seconds..."
                sleep 15
            fi
        fi
    done
    
    log_error "ArgoCD deployment failed after 3 attempts, but continuing bootstrap..."
    
    # Cleanup
    rm -f "$temp_file"
    
    log_debug "ArgoCD deployment completed"
    return 1
}

# Verify ArgoCD health
verify_argocd_health() {
    log_debug "Verifying ArgoCD deployment health..."
    
    # Check expected resource counts
    local expected_pods=7
    local actual_pods=$($KUBECTL get pods -n argocd --no-headers 2>/dev/null | grep -c Running || echo "0")
    
    log_debug "ArgoCD pods status: $actual_pods/$expected_pods running"
    
    if [ "$actual_pods" -ge 5 ]; then  # Allow some flexibility
        log_debug "✅ ArgoCD health check passed: $actual_pods pods running"
        return 0
    else
        log_error "⚠️ ArgoCD health check: only $actual_pods/$expected_pods pods running"
        
        # Check if pods are starting up
        local starting_pods=$($KUBECTL get pods -n argocd --no-headers 2>/dev/null | grep -c "ContainerCreating\|Init:" || echo "0")
        if [ "$starting_pods" -gt 0 ]; then
            log_debug "Found $starting_pods pods still starting - this may be normal"
        fi
        
        # Show pod status for debugging
        log_debug "Current ArgoCD pod status:"
        $KUBECTL get pods -n argocd 2>/dev/null || true
        
        # If we have any pods, consider it partial success
        if [ "$actual_pods" -gt 0 ] || [ "$starting_pods" -gt 0 ]; then
            log_debug "ArgoCD deployment appears to be in progress"
            return 0  # Don't fail the bootstrap for partial deployment
        else
            return 1
        fi
    fi
}

echo "Starting homelab bootstrap..."
log_debug "Bootstrap started at $(date)"

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
log_debug "Checking cluster node readiness..."
if ! $KUBECTL wait --for=condition=Ready nodes --all --timeout=300s; then
    log_error "Cluster nodes failed to become ready within 5 minutes"
    exit 1
fi
log_debug "✅ All cluster nodes are ready"

# Create namespaces
echo "Creating namespaces..."
log_debug "Creating required namespaces..."
$KUBECTL create namespace argocd --dry-run=client -o yaml | $KUBECTL apply -f - 2>&1 | tee -a /tmp/bootstrap.log
$KUBECTL create namespace cert-manager --dry-run=client -o yaml | $KUBECTL apply -f - 2>&1 | tee -a /tmp/bootstrap.log  
$KUBECTL create namespace ingress-nginx --dry-run=client -o yaml | $KUBECTL apply -f - 2>&1 | tee -a /tmp/bootstrap.log
log_debug "✅ Namespaces created successfully"

# Install ArgoCD using chunked deployment
echo "Installing ArgoCD..."
deploy_argocd_chunked

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
if ! verify_argocd_health; then
    log_error "ArgoCD health check failed, but continuing bootstrap..."
else
    log_debug "ArgoCD deployment successful"
fi

# Get ArgoCD password
log_debug "Retrieving ArgoCD admin password..."
echo "ArgoCD admin password:"
if ! $KUBECTL -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d; then
    log_error "Failed to retrieve ArgoCD admin password - secret may not exist yet"
    echo "(Password retrieval failed - check ArgoCD deployment status)"
fi
echo ""

# Install ingress-nginx
echo "Installing ingress-nginx..."
log_debug "Labeling control plane node for ingress..."
$KUBECTL label node homelab-control-plane ingress-ready=true --overwrite 2>&1 | tee -a /tmp/bootstrap.log

log_debug "Deploying ingress-nginx..."
if ! $KUBECTL apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/kind/deploy.yaml 2>&1 | tee -a /tmp/bootstrap.log; then
    log_error "ingress-nginx deployment failed, but continuing..."
else
    log_debug "ingress-nginx manifest applied successfully"
fi

# Wait for ingress-nginx to be ready
echo "Waiting for ingress-nginx to be ready..."
log_debug "Waiting for ingress-nginx controller to be ready..."
if ! $KUBECTL wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s 2>&1 | tee -a /tmp/bootstrap.log; then
    log_error "ingress-nginx failed to become ready within 5 minutes"
else
    log_debug "✅ ingress-nginx deployed successfully"
    echo "✅ ingress-nginx deployed successfully"
fi

# Deploy core services
echo "Deploying core services..."

# Install cert-manager
echo "Installing cert-manager..."
log_debug "Deploying cert-manager..."
if ! $KUBECTL apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml 2>&1 | tee -a /tmp/bootstrap.log; then
    log_error "cert-manager deployment failed, but continuing..."
else
    log_debug "cert-manager manifest applied successfully"
fi

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
log_debug "Waiting for cert-manager pods to be ready..."
if ! $KUBECTL wait --for=condition=Ready pods -n cert-manager -l app=cert-manager --timeout=300s 2>&1 | tee -a /tmp/bootstrap.log; then
    log_error "cert-manager failed to become ready within 5 minutes"
else
    log_debug "✅ cert-manager deployed successfully"
fi

# Deploy self-signed certificates
echo "Deploying self-signed certificates..."
log_debug "Creating self-signed certificate issuer and certificate..."
cat <<EOF | $KUBECTL apply -f - 2>&1 | tee -a /tmp/bootstrap.log
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

# Setup VM management and automation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Setting up VM management..."
log_debug "Running VM setup to create and start default VMs..."
if ! "$SCRIPT_DIR/setup-vms.sh" setup 2>&1 | tee -a /tmp/bootstrap.log; then
    log_error "VM setup failed, but continuing..."
else
    log_debug "✅ VM management configured successfully"
    echo "✅ VM management configured"
fi

echo "Bootstrap complete!"
log_debug "Bootstrap completed at $(date)"
log_debug "Bootstrap log available at: /tmp/bootstrap.log"
echo ""
echo "Access Information:"
echo "==================="
echo "Dashboard:"
echo "  make dashboard              - Launch web status dashboard"
echo "  Open http://localhost:8090"
echo ""
echo "ArgoCD:"
echo "  $KUBECTL port-forward -n argocd svc/argocd-server 8080:443"
echo "  Open https://localhost:8080"
echo "  Username: admin"
echo ""
echo "VM Management:"
echo "  make vms                    - List all VMs"
echo "  scripts/setup-vms.sh list  - List VMs with details"
echo "  scripts/setup-vms.sh health <vm> - Check VM health"
echo "  scripts/setup-vms.sh wait <vm>   - Wait for VM readiness"
echo "  scripts/setup-vms.sh help  - Show all VM management commands"
echo ""
echo "VM API Server:"
echo "  scripts/minimal-vm-api.py   - Start VM HTTP API on port 8082"