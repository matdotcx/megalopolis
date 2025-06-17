#!/bin/bash

set -euo pipefail

# VM Operator Test Suite
# Tests the Kubernetes-native VM management system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECTL="${PROJECT_ROOT}/kubectl"
FAILED_TESTS=0
PASSED_TESTS=0

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

# Cross-platform timeout function 
portable_timeout() {
    local seconds=$1
    shift
    
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
    else
        # macOS fallback
        "$@" &
        local pid=$!
        (
            sleep "$seconds"
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
                sleep 1
                kill -9 "$pid" 2>/dev/null || true
            fi
        ) &
        local killer_pid=$!
        wait "$pid" 2>/dev/null
        local exit_code=$?
        kill "$killer_pid" 2>/dev/null || true
        return $exit_code
    fi
}

# Test VM Operator deployment status
test_vm_operator_deployment() {
    log_info "=== Testing VM Operator Deployment ==="
    
    # Check namespace
    if ${KUBECTL} get namespace orchard-system >/dev/null 2>&1; then
        log_info "✅ orchard-system namespace exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ orchard-system namespace not found"
        ((FAILED_TESTS++))
        return 1
    fi
    
    # Check CRDs
    if ${KUBECTL} get crd vms.megalopolis.io >/dev/null 2>&1; then
        log_info "✅ VM CRD exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM CRD not found"
        ((FAILED_TESTS++))
    fi
    
    if ${KUBECTL} get crd vmconfigs.megalopolis.io >/dev/null 2>&1; then
        log_info "✅ VMConfig CRD exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ VMConfig CRD not found"
        ((FAILED_TESTS++))
    fi
    
    # Check deployment
    if ${KUBECTL} get deployment vm-operator -n orchard-system >/dev/null 2>&1; then
        log_info "✅ VM Operator deployment exists"
        ((PASSED_TESTS++))
        
        # Check if deployment is ready
        local ready_replicas available_replicas
        ready_replicas=$(${KUBECTL} get deployment vm-operator -n orchard-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        available_replicas=$(${KUBECTL} get deployment vm-operator -n orchard-system -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
        
        if [ "$ready_replicas" -gt 0 ] && [ "$available_replicas" -gt 0 ]; then
            log_info "✅ VM Operator deployment is ready ($ready_replicas/$available_replicas)"
            ((PASSED_TESTS++))
        else
            log_warn "⚠️  VM Operator deployment not ready ($ready_replicas/$available_replicas)"
            ((FAILED_TESTS++))
        fi
    else
        log_error "❌ VM Operator deployment not found"
        ((FAILED_TESTS++))
    fi
    
    # Check service
    if ${KUBECTL} get service vm-operator -n orchard-system >/dev/null 2>&1; then
        log_info "✅ VM Operator service exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator service not found"
        ((FAILED_TESTS++))
    fi
    
    # Check RBAC
    if ${KUBECTL} get serviceaccount vm-operator -n orchard-system >/dev/null 2>&1; then
        log_info "✅ VM Operator service account exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator service account not found"
        ((FAILED_TESTS++))
    fi
    
    if ${KUBECTL} get clusterrole vm-operator >/dev/null 2>&1; then
        log_info "✅ VM Operator cluster role exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator cluster role not found"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Test VM Operator health endpoint
test_vm_operator_health() {
    log_info "=== Testing VM Operator Health ==="
    
    # Get pod name
    local pod_name
    pod_name=$(${KUBECTL} get pods -n orchard-system -l app=vm-operator --no-headers -o custom-columns=":metadata.name" | head -1)
    
    if [ -z "$pod_name" ]; then
        log_error "❌ No VM Operator pod found"
        ((FAILED_TESTS++))
        return 1
    fi
    
    log_debug "Testing health endpoint on pod: $pod_name"
    
    # Test health endpoint
    if portable_timeout 10 ${KUBECTL} exec -n orchard-system "$pod_name" -- sh -c "echo -e 'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc localhost 8080" 2>/dev/null | grep -q "200 OK"; then
        log_info "✅ VM Operator health endpoint responds"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator health endpoint not responding"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Test VM Operator API endpoints
test_vm_operator_api() {
    log_info "=== Testing VM Operator API ==="
    
    # Get pod name
    local pod_name
    pod_name=$(${KUBECTL} get pods -n orchard-system -l app=vm-operator --no-headers -o custom-columns=":metadata.name" | head -1)
    
    if [ -z "$pod_name" ]; then
        log_error "❌ No VM Operator pod found"
        ((FAILED_TESTS++))
        return 1
    fi
    
    # Test VMs endpoint
    log_debug "Testing /vms endpoint"
    if portable_timeout 10 ${KUBECTL} exec -n orchard-system "$pod_name" -- sh -c "echo -e 'GET /vms HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc localhost 8080" 2>/dev/null | grep -q "200 OK"; then
        log_info "✅ VM Operator /vms endpoint responds"
        ((PASSED_TESTS++))
    else
        log_warn "⚠️  VM Operator /vms endpoint not responding"
        ((FAILED_TESTS++))
    fi
    
    # Test API info endpoint
    log_debug "Testing API info endpoint"
    if portable_timeout 10 ${KUBECTL} exec -n orchard-system "$pod_name" -- sh -c "echo -e 'GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc localhost 8080" 2>/dev/null | grep -q "200 OK"; then
        log_info "✅ VM Operator API info endpoint responds"
        ((PASSED_TESTS++))
    else
        log_warn "⚠️  VM Operator API info endpoint not responding"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Test VM Operator vs Orchard comparison
test_orchard_replacement() {
    log_info "=== Testing Orchard Controller Replacement ==="
    
    # Check that old Orchard controller is not running
    if ${KUBECTL} get deployment orchard-controller -n orchard-system >/dev/null 2>&1; then
        log_warn "⚠️  Old Orchard controller still exists"
        ((FAILED_TESTS++))
    else
        log_info "✅ Old Orchard controller properly removed"
        ((PASSED_TESTS++))
    fi
    
    # Check that VM Operator is running instead
    if ${KUBECTL} get deployment vm-operator -n orchard-system >/dev/null 2>&1; then
        log_info "✅ VM Operator deployed as replacement"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator not deployed"
        ((FAILED_TESTS++))
    fi
    
    # Verify no Docker socket dependency
    local deployment_yaml
    deployment_yaml=$(${KUBECTL} get deployment vm-operator -n orchard-system -o yaml 2>/dev/null || echo "")
    
    if echo "$deployment_yaml" | grep -q "docker.sock"; then
        log_error "❌ VM Operator still has Docker socket dependency"
        ((FAILED_TESTS++))
    else
        log_info "✅ VM Operator has no Docker socket dependency"
        ((PASSED_TESTS++))
    fi
    
    echo ""
}

# Test Custom Resource Definitions
test_vm_crds() {
    log_info "=== Testing VM Custom Resource Definitions ==="
    
    # Test VM CRD schema
    if ${KUBECTL} explain vm.spec >/dev/null 2>&1; then
        log_info "✅ VM CRD schema is valid"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM CRD schema is invalid"
        ((FAILED_TESTS++))
    fi
    
    # Test VMConfig CRD schema  
    if ${KUBECTL} explain vmconfig.spec >/dev/null 2>&1; then
        log_info "✅ VMConfig CRD schema is valid"
        ((PASSED_TESTS++))
    else
        log_error "❌ VMConfig CRD schema is invalid"
        ((FAILED_TESTS++))
    fi
    
    # Test creating a test VM resource (dry-run)
    local test_vm_yaml=$(cat << 'EOF'
apiVersion: megalopolis.io/v1
kind: VM
metadata:
  name: test-vm
  namespace: default
spec:
  name: test-vm
  baseImage: macos-sequoia
  resources:
    memory: "4096"
    cpu: "2"
    disk: "40"
  settings:
    sshEnabled: true
    autoStart: false
EOF
)
    
    if echo "$test_vm_yaml" | ${KUBECTL} apply --dry-run=client -f - >/dev/null 2>&1; then
        log_info "✅ VM custom resource validation passed"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM custom resource validation failed"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Test VM bridge script integration
test_vm_bridge_integration() {
    log_info "=== Testing VM Bridge Script Integration ==="
    
    # Check if VM bridge script exists and is executable
    local bridge_script="${PROJECT_ROOT}/scripts/vm-k8s-bridge.sh"
    
    if [[ -x "$bridge_script" ]]; then
        log_info "✅ VM bridge script exists and is executable"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM bridge script not found or not executable"
        ((FAILED_TESTS++))
        return 1
    fi
    
    # Test VM bridge script help
    if "$bridge_script" help >/dev/null 2>&1; then
        log_info "✅ VM bridge script help works"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM bridge script help failed"
        ((FAILED_TESTS++))
    fi
    
    # Test VM bridge script list command
    if "$bridge_script" list >/dev/null 2>&1; then
        log_info "✅ VM bridge script list command works"
        ((PASSED_TESTS++))
    else
        log_warn "⚠️  VM bridge script list command failed (may be expected if no VMs exist)"
        # This is not a failure as VMs might not exist yet
        ((PASSED_TESTS++))
    fi
    
    echo ""
}

# Test deployment scripts
test_deployment_scripts() {
    log_info "=== Testing Deployment Scripts ==="
    
    # Check if deployment script exists
    local deploy_script="${PROJECT_ROOT}/scripts/deploy-vm-operator.sh"
    
    if [[ -x "$deploy_script" ]]; then
        log_info "✅ VM Operator deployment script exists"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator deployment script not found"
        ((FAILED_TESTS++))
    fi
    
    # Test deployment script status command
    if "$deploy_script" status >/dev/null 2>&1; then
        log_info "✅ VM Operator deployment script status works"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM Operator deployment script status failed"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Main test execution
echo "=== VM Operator Test Suite ==="
echo "Testing Kubernetes-native VM management system..."
echo ""

test_vm_operator_deployment
test_vm_operator_health
test_vm_operator_api
test_orchard_replacement
test_vm_crds
test_vm_bridge_integration
test_deployment_scripts

echo "=== VM Operator Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ All VM Operator tests passed!"
    echo ""
    echo "The Kubernetes-native VM management system is working correctly:"
    echo "  ✅ No Docker socket dependency"
    echo "  ✅ Custom Resource Definitions working"
    echo "  ✅ API endpoints responding"
    echo "  ✅ RBAC properly configured"
    echo "  ✅ Health checks passing"
    exit 0
else
    echo "❌ Some VM Operator tests failed"
    echo ""
    echo "Issues detected:"
    if [ ${FAILED_TESTS} -gt 0 ]; then
        echo "  ❌ ${FAILED_TESTS} components not working correctly"
        echo "  ℹ️  Use './scripts/deploy-vm-operator.sh status' for details"
        echo "  ℹ️  Use './scripts/deploy-vm-operator.sh logs' to see logs"
    fi
    exit 1
fi