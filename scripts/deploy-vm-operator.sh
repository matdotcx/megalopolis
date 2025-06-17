#!/bin/bash
set -euo pipefail

# Deploy VM Operator - Kubernetes-native VM management
# This replaces the Docker-dependent Orchard controller

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECTL="${PROJECT_ROOT}/kubectl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if [[ ! -x "$KUBECTL" ]]; then
        log_error "kubectl not found at $KUBECTL"
        exit 1
    fi
    
    if ! "$KUBECTL" cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

# Remove old Orchard controller if it exists
remove_old_orchard() {
    log_info "Checking for existing Orchard controller..."
    
    if "$KUBECTL" get deployment orchard-controller -n orchard-system >/dev/null 2>&1; then
        log_warn "Found existing Orchard controller, removing..."
        
        # Delete the deployment
        "$KUBECTL" delete deployment orchard-controller -n orchard-system || true
        
        # Delete the service if it exists
        "$KUBECTL" delete service orchard-controller -n orchard-system || true
        
        # Remove the old RBAC
        "$KUBECTL" delete clusterrolebinding orchard-controller || true
        "$KUBECTL" delete clusterrole orchard-controller || true
        "$KUBECTL" delete serviceaccount orchard-controller -n orchard-system || true
        
        log_info "Old Orchard controller removed"
    else
        log_info "No existing Orchard controller found"
    fi
}

# Create namespace if it doesn't exist
create_namespace() {
    log_info "Creating orchard-system namespace..."
    
    if ! "$KUBECTL" get namespace orchard-system >/dev/null 2>&1; then
        "$KUBECTL" create namespace orchard-system
        log_info "Namespace orchard-system created"
    else
        log_info "Namespace orchard-system already exists"
    fi
}

# Deploy Custom Resource Definitions
deploy_crds() {
    log_info "Deploying VM Custom Resource Definitions..."
    
    "$KUBECTL" apply -f "${PROJECT_ROOT}/k8s-manifests/vm-crd.yaml"
    
    # Wait for CRDs to be established
    log_info "Waiting for CRDs to be established..."
    "$KUBECTL" wait --for condition=established --timeout=60s crd/vms.megalopolis.io
    "$KUBECTL" wait --for condition=established --timeout=60s crd/vmconfigs.megalopolis.io
    
    log_info "CRDs deployed successfully"
}

# Deploy RBAC
deploy_rbac() {
    log_info "Deploying VM Operator RBAC..."
    
    "$KUBECTL" apply -f "${PROJECT_ROOT}/k8s-manifests/vm-operator-rbac.yaml"
    
    log_info "RBAC deployed successfully"
}

# Deploy VM Operator
deploy_vm_operator() {
    log_info "Deploying VM Operator..."
    
    "$KUBECTL" apply -f "${PROJECT_ROOT}/k8s-manifests/vm-operator-deployment.yaml"
    
    # Wait for deployment to be ready
    log_info "Waiting for VM Operator to be ready..."
    "$KUBECTL" rollout status deployment/vm-operator -n orchard-system --timeout=120s
    
    log_info "VM Operator deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying VM Operator deployment..."
    
    # Check if pod is running
    local pod_status
    pod_status=$("$KUBECTL" get pods -n orchard-system -l app=vm-operator --no-headers | awk '{print $3}' | head -1)
    
    if [ "$pod_status" = "Running" ]; then
        log_info "✅ VM Operator pod is running"
    else
        log_warn "⚠️  VM Operator pod status: $pod_status"
    fi
    
    # Check if service is available
    if "$KUBECTL" get service vm-operator -n orchard-system >/dev/null 2>&1; then
        log_info "✅ VM Operator service is available"
    else
        log_warn "⚠️  VM Operator service not found"
    fi
    
    # Test health endpoint
    log_info "Testing VM Operator health endpoint..."
    if "$KUBECTL" exec -n orchard-system deployment/vm-operator -- wget -q -O- http://localhost:8080/health >/dev/null 2>&1; then
        log_info "✅ VM Operator health check passed"
    else
        log_warn "⚠️  VM Operator health check failed"
    fi
}

# Show access information
show_access_info() {
    log_info "VM Operator Access Information:"
    echo ""
    echo "📊 Dashboard Access:"
    echo "  kubectl port-forward -n orchard-system svc/vm-operator 8081:8080"
    echo "  Then visit: http://localhost:8081"
    echo ""
    echo "🔧 API Endpoints:"
    echo "  GET  /health         - Health check"
    echo "  GET  /vms            - List all VMs"
    echo "  GET  /vms/{name}     - Get VM details"
    echo "  POST /vms/{name}/start - Start VM"
    echo "  POST /vms/{name}/stop  - Stop VM"
    echo "  DELETE /vms/{name}   - Delete VM"
    echo ""
    echo "🏠 Local VM Management:"
    echo "  The VM Operator provides a Kubernetes-native interface"
    echo "  VM operations are still performed via Tart CLI on the host"
    echo "  Use the enhanced setup-vms.sh script for direct VM management"
    echo ""
}

# Main deployment function
main() {
    log_info "🚀 Deploying VM Operator (Kubernetes-native VM management)"
    echo ""
    
    check_kubectl
    create_namespace
    remove_old_orchard
    deploy_crds
    deploy_rbac
    deploy_vm_operator
    verify_deployment
    
    echo ""
    log_info "✅ VM Operator deployment completed!"
    echo ""
    
    show_access_info
}

# Parse command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "remove")
        log_info "🗑️  Removing VM Operator..."
        
        # Remove deployments
        "$KUBECTL" delete -f "${PROJECT_ROOT}/k8s-manifests/vm-operator-deployment.yaml" || true
        
        # Remove RBAC
        "$KUBECTL" delete -f "${PROJECT_ROOT}/k8s-manifests/vm-operator-rbac.yaml" || true
        
        # Remove CRDs (this will also remove all VM resources)
        log_warn "This will remove all VM custom resources!"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            "$KUBECTL" delete -f "${PROJECT_ROOT}/k8s-manifests/vm-crd.yaml" || true
        fi
        
        log_info "VM Operator removed"
        ;;
    "status")
        log_info "VM Operator Status:"
        echo ""
        
        # Check namespace
        if "$KUBECTL" get namespace orchard-system >/dev/null 2>&1; then
            echo "✅ Namespace: orchard-system exists"
        else
            echo "❌ Namespace: orchard-system not found"
        fi
        
        # Check CRDs
        if "$KUBECTL" get crd vms.megalopolis.io >/dev/null 2>&1; then
            echo "✅ CRD: vms.megalopolis.io exists"
        else
            echo "❌ CRD: vms.megalopolis.io not found"
        fi
        
        # Check deployment
        if "$KUBECTL" get deployment vm-operator -n orchard-system >/dev/null 2>&1; then
            local replicas_status
            replicas_status=$("$KUBECTL" get deployment vm-operator -n orchard-system -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')
            echo "✅ Deployment: vm-operator ($replicas_status ready)"
        else
            echo "❌ Deployment: vm-operator not found"
        fi
        
        # Check service
        if "$KUBECTL" get service vm-operator -n orchard-system >/dev/null 2>&1; then
            echo "✅ Service: vm-operator exists"
        else
            echo "❌ Service: vm-operator not found"
        fi
        ;;
    "logs")
        log_info "VM Operator Logs:"
        "$KUBECTL" logs -n orchard-system deployment/vm-operator --tail=50 -f
        ;;
    "help"|"-h"|"--help")
        echo "VM Operator Deployment Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy    Deploy VM Operator (default)"
        echo "  remove    Remove VM Operator"
        echo "  status    Show VM Operator status"
        echo "  logs      Show VM Operator logs"
        echo ""
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac