#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECTL="${PROJECT_ROOT}/kubectl"
TART="${PROJECT_ROOT}/tart-binary"
FAILED_TESTS=0
PASSED_TESTS=0

echo "=== End-to-End Validation Test ==="
echo "Testing complete infrastructure integration..."
echo ""

# Test VM to Kubernetes communication
echo "Testing VM to Kubernetes integration..."

# Get a running VM IP
vm_ip=$(${TART} list 2>/dev/null | grep "running" | head -1 | awk '{print $1}' | xargs -I {} ${TART} ip {} 2>/dev/null || echo "")

if [ -n "${vm_ip}" ]; then
    echo "✅ Found VM with IP: ${vm_ip}"
    ((PASSED_TESTS++))
    
    # Test if VM can reach Kubernetes API (through host)
    echo "Testing if VM can reach Kubernetes API through host..."
    host_ip=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "host.docker.internal")
    
    if [ -n "${host_ip}" ]; then
        # Test connectivity from VM to host
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR "admin@${vm_ip}" "ping -c 1 ${host_ip}" &>/dev/null; then
            echo "  ✅ VM can reach host network"
            ((PASSED_TESTS++))
        else
            echo "  ❌ VM cannot reach host network"
            ((FAILED_TESTS++))
        fi
    fi
else
    echo "❌ No running VMs found for integration testing"
    ((FAILED_TESTS++))
fi

echo ""

# Test ArgoCD application deployment capability
echo "Testing ArgoCD GitOps capability..."
if ${KUBECTL} get namespace argocd &>/dev/null && \
   ${KUBECTL} get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo "✅ ArgoCD is ready for GitOps deployments"
    ((PASSED_TESTS++))
    
    # Check if ArgoCD can create applications
    if ${KUBECTL} auth can-i create applications.argoproj.io -n argocd &>/dev/null; then
        echo "✅ ArgoCD has permissions to manage applications"
        ((PASSED_TESTS++))
    else
        echo "❌ ArgoCD lacks permissions for application management"
        ((FAILED_TESTS++))
    fi
else
    echo "❌ ArgoCD is not ready"
    ((FAILED_TESTS++))
fi

echo ""

# Test Orchard VM management integration
echo "Testing Orchard VM management..."
if ${KUBECTL} get namespace orchard-system &>/dev/null && \
   ${KUBECTL} get pods -n orchard-system -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo "✅ Orchard controller is running"
    ((PASSED_TESTS++))
    
    # Check if Orchard can see VMs
    orchard_endpoint="http://localhost:8081"
    
    # Try to setup port-forward and test
    ${KUBECTL} port-forward -n orchard-system svc/orchard-controller 8081:8080 &>/dev/null &
    pf_pid=$!
    sleep 3
    
    if curl --connect-timeout 5 -s "${orchard_endpoint}/healthz" &>/dev/null; then
        echo "✅ Orchard API is accessible"
        ((PASSED_TESTS++))
    else
        echo "❌ Orchard API is not accessible"
        ((FAILED_TESTS++))
    fi
    
    kill ${pf_pid} 2>/dev/null || true
    wait ${pf_pid} 2>/dev/null || true
else
    echo "❌ Orchard controller is not running"
    ((FAILED_TESTS++))
fi

echo ""

# Test resource availability
echo "Testing resource allocation..."

# Check Kubernetes node resources
node_cpu=$(${KUBECTL} get nodes -o jsonpath='{.items[0].status.allocatable.cpu}' 2>/dev/null || echo "0")
node_memory=$(${KUBECTL} get nodes -o jsonpath='{.items[0].status.allocatable.memory}' 2>/dev/null || echo "0")

if [ -n "${node_cpu}" ] && [ "${node_cpu}" != "0" ]; then
    echo "✅ Kubernetes node has ${node_cpu} CPUs allocated"
    ((PASSED_TESTS++))
else
    echo "❌ Cannot determine Kubernetes node CPU allocation"
    ((FAILED_TESTS++))
fi

if [ -n "${node_memory}" ] && [ "${node_memory}" != "0" ]; then
    echo "✅ Kubernetes node has ${node_memory} memory allocated"
    ((PASSED_TESTS++))
else
    echo "❌ Cannot determine Kubernetes node memory allocation"
    ((FAILED_TESTS++))
fi

# Check VM resources
total_vm_cpus=0
total_vm_memory=0
vm_count=0

while IFS= read -r vm_name; do
    if [ -n "${vm_name}" ] && [ "${vm_name}" != "NAME" ]; then
        ((vm_count++))
        # Note: Actual resource queries would require more complex parsing
        # For now, we just count VMs
    fi
done < <(${TART} list 2>/dev/null | awk '{print $1}')

if [ ${vm_count} -gt 0 ]; then
    echo "✅ Found ${vm_count} VMs provisioned"
    ((PASSED_TESTS++))
else
    echo "❌ No VMs found"
    ((FAILED_TESTS++))
fi

echo ""

# Test service mesh readiness
echo "Testing service mesh readiness..."
if ${KUBECTL} get namespace ingress-nginx &>/dev/null; then
    echo "✅ Ingress controller namespace exists"
    ((PASSED_TESTS++))
else
    echo "❌ Ingress controller namespace not found"
    ((FAILED_TESTS++))
fi

if ${KUBECTL} get namespace cert-manager &>/dev/null; then
    echo "✅ Certificate manager namespace exists"
    ((PASSED_TESTS++))
else
    echo "❌ Certificate manager namespace not found"
    ((FAILED_TESTS++))
fi

echo ""
echo "=== E2E Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ End-to-end validation passed!"
    exit 0
else
    echo "❌ End-to-end validation failed"
    exit 1
fi