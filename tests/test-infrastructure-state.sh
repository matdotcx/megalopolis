#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECTL="${PROJECT_ROOT}/kubectl"
KIND="${PROJECT_ROOT}/kind-binary"
TART="${PROJECT_ROOT}/tart-binary"
FAILED_TESTS=0
PASSED_TESTS=0

echo "=== Infrastructure State Test ==="
echo "Validating expected state after fresh install..."
echo ""

# Test Docker
echo "Testing Docker availability..."
if docker info &>/dev/null; then
    echo "✅ Docker is running"
    ((PASSED_TESTS++))
else
    echo "❌ Docker is not running or not installed"
    ((FAILED_TESTS++))
fi

# Test Kind cluster
echo ""
echo "Testing Kind cluster..."
if ${KIND} get clusters 2>/dev/null | grep -q "homelab"; then
    echo "✅ Kind cluster 'homelab' exists"
    ((PASSED_TESTS++))
    
    # Check if cluster is running
    if docker ps | grep -q "homelab-control-plane"; then
        echo "✅ Cluster control plane is running"
        ((PASSED_TESTS++))
    else
        echo "❌ Cluster control plane is not running"
        ((FAILED_TESTS++))
    fi
else
    echo "❌ Kind cluster 'homelab' not found"
    ((FAILED_TESTS++))
fi

# Test kubectl configuration
echo ""
echo "Testing kubectl configuration..."
if [ -f ~/.kube/config ]; then
    echo "✅ Kubeconfig exists"
    ((PASSED_TESTS++))
    
    # Test if kubectl can connect
    if ${KUBECTL} version &>/dev/null; then
        echo "✅ kubectl can connect to cluster"
        ((PASSED_TESTS++))
    else
        echo "❌ kubectl cannot connect to cluster"
        ((FAILED_TESTS++))
    fi
else
    echo "❌ Kubeconfig not found"
    ((FAILED_TESTS++))
fi

# Test Tart installation
echo ""
echo "Testing Tart installation..."
if [ -f "${TART}" ] && [ -x "${TART}" ]; then
    echo "✅ Tart binary exists and is executable"
    ((PASSED_TESTS++))
    
    # Check if Tart can run
    if ${TART} list &>/dev/null; then
        echo "✅ Tart is functional"
        ((PASSED_TESTS++))
    else
        echo "❌ Tart cannot execute (may need sudo or initialization)"
        ((FAILED_TESTS++))
    fi
else
    echo "❌ Tart binary not found or not executable"
    ((FAILED_TESTS++))
fi

# Test expected VMs exist
echo ""
echo "Testing VM infrastructure..."
vm_count=$(${TART} list 2>/dev/null | grep -c "running" || echo "0")
echo "Found ${vm_count} running VMs"

if ${TART} list 2>/dev/null | grep -q "^macos-dev[[:space:]]"; then
    echo "✅ macos-dev VM exists"
    ((PASSED_TESTS++))
else
    echo "⚠️  macos-dev VM not found (may require authenticated image pull)"
    echo "   Note: VM creation requires authenticated access to ghcr.io/cirruslabs images"
fi

if ${TART} list 2>/dev/null | grep -q "^macos-ci[[:space:]]"; then
    echo "✅ macos-ci VM exists"
    ((PASSED_TESTS++))
else
    echo "⚠️  macos-ci VM not found (may require authenticated image pull)"
    echo "   Note: VM creation requires authenticated access to ghcr.io/cirruslabs images"
fi

# Test network connectivity
echo ""
echo "Testing network configuration..."
if docker network ls --format "table {{.Name}}" | tail -n +2 | grep -q "^kind$"; then
    echo "✅ Kind network exists"
    ((PASSED_TESTS++))
else
    echo "❌ Kind network not found"
    ((FAILED_TESTS++))
fi

# Test if we can reach cluster from host
api_port=$(${KUBECTL} cluster-info 2>/dev/null | grep -oE 'https://[0-9.:]+' | head -1 | sed 's|https://||' | cut -d: -f2 || echo "")
if [ -n "${api_port}" ] && nc -z localhost "${api_port}" 2>/dev/null; then
    echo "✅ Kubernetes API server is accessible on port ${api_port}"
    ((PASSED_TESTS++))
else
    echo "❌ Cannot reach Kubernetes API server"
    ((FAILED_TESTS++))
fi

echo ""
echo "=== State Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ Infrastructure state validation passed!"
    exit 0
else
    echo "❌ Infrastructure state validation failed"
    exit 1
fi