#!/bin/bash
set -euo pipefail

# Simple deployment validation for Megalopolis
# Tests the core functionality after deployment

echo "🧪 Megalopolis Deployment Validation"
echo "===================================="

KUBECTL="./kubectl"
TART="tart"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

passed=0
failed=0

test_passed() {
    echo "✅ $1"
    ((passed++))
}

test_failed() {
    echo "❌ $1"
    ((failed++))
}

# Test 1: Kubernetes cluster
echo ""
echo "📋 Testing Kubernetes cluster..."
if $KUBECTL cluster-info &>/dev/null; then
    test_passed "Kubernetes cluster is accessible"
else
    test_failed "Kubernetes cluster is not accessible"
fi

# Test 2: Node readiness
if [ $($KUBECTL get nodes --no-headers | grep "Ready" | wc -l) -eq 4 ]; then
    test_passed "All 4 nodes are ready"
else
    test_failed "Not all nodes are ready"
fi

# Test 3: ArgoCD
echo ""
echo "📋 Testing ArgoCD..."
argocd_pods=$($KUBECTL get pods -n argocd --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
if [ "$argocd_pods" -ge 7 ]; then
    test_passed "ArgoCD is running ($argocd_pods pods)"
else
    test_failed "ArgoCD is not fully running ($argocd_pods pods)"
fi

# Test 4: cert-manager
echo ""
echo "📋 Testing cert-manager..."
certmanager_pods=$($KUBECTL get pods -n cert-manager --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
if [ "$certmanager_pods" -ge 3 ]; then
    test_passed "cert-manager is running ($certmanager_pods pods)"
else
    test_failed "cert-manager is not fully running ($certmanager_pods pods)"
fi

# Test 5: ingress-nginx
echo ""
echo "📋 Testing ingress-nginx..."
ingress_pods=$($KUBECTL get pods -n ingress-nginx --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
if [ "$ingress_pods" -ge 1 ]; then
    test_passed "ingress-nginx is running ($ingress_pods pods)"
else
    test_failed "ingress-nginx is not running"
fi

# Test 6: VMs
echo ""
echo "📋 Testing Virtual Machines..."
if command -v $TART >/dev/null 2>&1; then
    running_vms=$($TART list 2>/dev/null | grep "running" | wc -l || echo "0")
    if [ "$running_vms" -ge 2 ]; then
        test_passed "VMs are running ($running_vms running)"
    else
        test_failed "VMs are not running ($running_vms running)"
    fi
    
    # Test specific VMs
    if $TART list 2>/dev/null | grep -q "macos-dev.*running"; then
        test_passed "macos-dev VM is running"
    else
        test_failed "macos-dev VM is not running"
    fi
    
    if $TART list 2>/dev/null | grep -q "macos-ci.*running"; then
        test_passed "macos-ci VM is running"
    else
        test_failed "macos-ci VM is not running"
    fi
else
    test_failed "Tart command not available"
fi

# Test 7: Dashboard API
echo ""
echo "📋 Testing Dashboard API..."
if curl -s -f http://localhost:8090/api/status >/dev/null 2>&1; then
    test_passed "Dashboard API is responding"
    
    # Check if status shows healthy services
    healthy_count=$(curl -s http://localhost:8090/api/status | grep -o '"healthy":[[:space:]]*[0-9]*' | grep -o '[0-9]*' || echo "0")
    if [ "$healthy_count" -ge 10 ]; then
        test_passed "Dashboard shows healthy services ($healthy_count healthy)"
    else
        test_failed "Dashboard shows unhealthy services ($healthy_count healthy)"
    fi
else
    test_failed "Dashboard API is not responding"
fi

# Test 8: No failed pods
echo ""
echo "📋 Testing for failed pods..."
failed_pods=$($KUBECTL get pods -A --no-headers 2>/dev/null | grep -E "(Failed|Error|CrashLoopBackOff)" | wc -l || echo "0")
if [ "$failed_pods" -eq 0 ]; then
    test_passed "No failed pods found"
else
    test_failed "Found $failed_pods failed pods"
fi

# Summary
echo ""
echo "📊 Validation Summary"
echo "===================="
echo "✅ Passed: $passed"
echo "❌ Failed: $failed"

if [ "$failed" -eq 0 ]; then
    echo ""
    echo "🎉 All tests passed! Megalopolis is operational."
    exit 0
else
    echo ""
    echo "⚠️  Some tests failed. Please check the output above."
    exit 1
fi