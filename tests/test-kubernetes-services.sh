#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECTL="${PROJECT_ROOT}/kubectl"
FAILED_TESTS=0
PASSED_TESTS=0

echo "=== Kubernetes Services Test Suite ==="
echo "Testing Kubernetes cluster and service availability..."
echo ""

# Function to check if a namespace exists
check_namespace() {
    local namespace=$1
    echo -n "Checking namespace ${namespace}... "
    if ${KUBECTL} get namespace "${namespace}" &>/dev/null; then
        echo "✅ Exists"
        ((PASSED_TESTS++))
        return 0
    else
        echo "❌ Not found"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Function to check if pods are running in a namespace
check_pods_running() {
    local namespace=$1
    local expected_pods=$2
    
    echo "Checking pods in namespace ${namespace}..."
    local running_pods=$(${KUBECTL} get pods -n "${namespace}" --no-headers 2>/dev/null | grep "Running" | wc -l | tr -d ' ')
    
    if [ "${running_pods}" -ge "${expected_pods}" ]; then
        echo "  ✅ Found ${running_pods} running pods (expected at least ${expected_pods})"
        ((PASSED_TESTS++))
        return 0
    else
        echo "  ❌ Only ${running_pods} running pods (expected at least ${expected_pods})"
        ${KUBECTL} get pods -n "${namespace}" 2>/dev/null || true
        ((FAILED_TESTS++))
        return 1
    fi
}

# Function to test service endpoint
test_service_endpoint() {
    local service_name=$1
    local namespace=$2
    local port=$3
    local local_port=$4
    local protocol=${5:-"http"}
    
    echo "Testing ${service_name} service..."
    
    # Check if service exists
    if ! ${KUBECTL} get service "${service_name}" -n "${namespace}" &>/dev/null; then
        echo "  ❌ Service ${service_name} not found in namespace ${namespace}"
        ((FAILED_TESTS++))
        return 1
    fi
    
    echo "  ✅ Service exists"
    ((PASSED_TESTS++))
    
    # Test port-forward in background
    echo "  Setting up port-forward to localhost:${local_port}..."
    ${KUBECTL} port-forward -n "${namespace}" "svc/${service_name}" "${local_port}:${port}" &>/dev/null &
    local pf_pid=$!
    
    # Give port-forward time to establish
    sleep 3
    
    # Test connectivity
    local test_url="${protocol}://localhost:${local_port}"
    if [ "${protocol}" == "https" ]; then
        # For HTTPS, use curl with insecure flag
        if curl -sk --connect-timeout 5 "${test_url}" -o /dev/null 2>/dev/null; then
            echo "  ✅ Service responding on ${test_url}"
            ((PASSED_TESTS++))
        else
            echo "  ❌ Service not responding on ${test_url}"
            ((FAILED_TESTS++))
        fi
    else
        # For HTTP, use nc or curl
        if nc -z localhost "${local_port}" 2>/dev/null; then
            echo "  ✅ Port ${local_port} is accessible"
            ((PASSED_TESTS++))
        else
            echo "  ❌ Port ${local_port} is not accessible"
            ((FAILED_TESTS++))
        fi
    fi
    
    # Clean up port-forward
    kill ${pf_pid} 2>/dev/null || true
    wait ${pf_pid} 2>/dev/null || true
    
    echo ""
}

# Test cluster connectivity
echo "Testing cluster connectivity..."
if ${KUBECTL} cluster-info &>/dev/null; then
    echo "✅ Cluster is accessible"
    ((PASSED_TESTS++))
    ${KUBECTL} cluster-info
else
    echo "❌ Cannot connect to cluster"
    ((FAILED_TESTS++))
    exit 1
fi

echo ""

# Test nodes
echo "Testing cluster nodes..."
node_count=$(${KUBECTL} get nodes --no-headers 2>/dev/null | wc -l)
ready_nodes=$(${KUBECTL} get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")

if [ "${node_count}" -gt 0 ] && [ "${ready_nodes}" -eq "${node_count}" ]; then
    echo "✅ All ${node_count} nodes are ready"
    ((PASSED_TESTS++))
else
    echo "❌ ${ready_nodes} of ${node_count} nodes are ready"
    ((FAILED_TESTS++))
fi

echo ""

# Test expected namespaces
echo "Testing expected namespaces..."
check_namespace "kube-system"
check_namespace "argocd"
check_namespace "orchard-system"
check_namespace "cert-manager"
check_namespace "ingress-nginx"
check_namespace "external-secrets"
check_namespace "monitoring"
check_namespace "keycloak"

echo ""

# Test core services
echo "Testing core services..."

# Test ArgoCD
if check_namespace "argocd"; then
    check_pods_running "argocd" 1
    test_service_endpoint "argocd-server" "argocd" "443" "8080" "https"
    
    # Check if we can get ArgoCD password
    echo "Testing ArgoCD credentials..."
    if ${KUBECTL} get secret argocd-initial-admin-secret -n argocd &>/dev/null; then
        echo "  ✅ ArgoCD admin secret exists"
        ((PASSED_TESTS++))
    else
        echo "  ❌ ArgoCD admin secret not found"
        ((FAILED_TESTS++))
    fi
fi

echo ""

# Test Orchard
if check_namespace "orchard-system"; then
    check_pods_running "orchard-system" 1
    test_service_endpoint "orchard-controller" "orchard-system" "8080" "8081" "http"
    
    # Test NodePort service
    echo "Testing Orchard NodePort service..."
    if ${KUBECTL} get service orchard-controller-nodeport -n orchard-system &>/dev/null; then
        echo "  ✅ NodePort service exists"
        ((PASSED_TESTS++))
        
        # Check if NodePort 30080 is configured
        nodeport=$(${KUBECTL} get service orchard-controller-nodeport -n orchard-system -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        if [ "${nodeport}" == "30080" ]; then
            echo "  ✅ NodePort configured on port 30080"
            ((PASSED_TESTS++))
        else
            echo "  ❌ NodePort is ${nodeport}, expected 30080"
            ((FAILED_TESTS++))
        fi
    else
        echo "  ❌ NodePort service not found"
        ((FAILED_TESTS++))
    fi
fi

echo ""
echo "=== Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ All Kubernetes service tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi