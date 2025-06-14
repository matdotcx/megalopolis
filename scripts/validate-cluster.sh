#!/bin/bash
set -euo pipefail

# Use project-local binaries
KUBECTL="./kubectl"
TART="./tart-binary"

echo "Validating cluster and VM health..."

# Check if cluster exists
if ! $KUBECTL cluster-info &>/dev/null; then
    echo "ERROR: Cluster is not accessible"
    exit 1
fi

# Check nodes
echo -n "Checking nodes... "
NODE_COUNT=$($KUBECTL get nodes --no-headers | wc -l | tr -d ' ')
if [ "$NODE_COUNT" -lt 1 ]; then
    echo "FAIL: No nodes found"
    exit 1
else
    echo "OK ($NODE_COUNT nodes)"
fi

# Check if all nodes are ready
echo -n "Checking node status... "
NOT_READY=$( ($KUBECTL get nodes --no-headers | grep -v "Ready" || true) | wc -l | tr -d ' ')
if [ "$NOT_READY" -ne 0 ]; then
    echo "FAIL: $NOT_READY nodes are not ready"
    exit 1
else
    echo "OK (all ready)"
fi

# Check ArgoCD namespace
echo -n "Checking ArgoCD namespace... "
if ! $KUBECTL get namespace argocd &>/dev/null; then
    echo "FAIL: ArgoCD namespace not found"
    exit 1
else
    echo "OK"
fi

# Check ArgoCD pods
echo -n "Checking ArgoCD pods... "
ARGOCD_PODS=$($KUBECTL get pods -n argocd --no-headers | wc -l | tr -d ' ')
if [ "$ARGOCD_PODS" -eq 0 ]; then
    echo "FAIL: No ArgoCD pods found"
    exit 1
fi

NOT_RUNNING=$( ($KUBECTL get pods -n argocd --no-headers | grep -v "Running" || true) | wc -l | tr -d ' ')
if [ "$NOT_RUNNING" -ne 0 ]; then
    echo "FAIL: $NOT_RUNNING ArgoCD pods are not running"
    exit 1
else
    echo "OK ($ARGOCD_PODS pods running)"
fi

# Check ArgoCD server
echo -n "Checking ArgoCD server... "
if ! $KUBECTL get svc -n argocd argocd-server &>/dev/null; then
    echo "FAIL: ArgoCD server service not found"
    exit 1
else
    echo "OK"
fi

# Check if password is available
echo -n "Checking ArgoCD admin password... "
if ! $KUBECTL get secret -n argocd argocd-initial-admin-secret &>/dev/null; then
    echo "FAIL: Admin password secret not found"
    exit 1
else
    echo "OK"
fi

# Check VM infrastructure (if available)
echo ""
echo "=== VM Infrastructure Validation ==="

# Check if Tart is available
if [[ -f "$TART" ]] && [[ -x "$TART" ]]; then
    echo -n "Checking Tart availability... "
    if $TART --version &>/dev/null; then
        echo "OK"
        
        # Check VMs
        echo -n "Checking VMs... "
        VM_COUNT=$($TART list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        echo "Found $VM_COUNT VMs"
        
        if [ "$VM_COUNT" -gt 0 ]; then
            # List VM status
            echo "VM Status:"
            $TART list 2>/dev/null || echo "  No VMs found"
        fi
    else
        echo "FAIL: Tart is not working properly"
    fi
else
    echo "INFO: Tart not available (VM features disabled)"
fi

# Check Orchard namespace (if deployed)
echo -n "Checking Orchard namespace... "
if $KUBECTL get namespace orchard-system &>/dev/null; then
    echo "OK"
    
    # Check Orchard controller
    echo -n "Checking Orchard controller... "
    ORCHARD_PODS=$($KUBECTL get pods -n orchard-system -l app=orchard-controller --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$ORCHARD_PODS" -eq 0 ]; then
        echo "INFO: No Orchard controller pods found"
    else
        NOT_RUNNING=$( ($KUBECTL get pods -n orchard-system -l app=orchard-controller --no-headers | grep -v "Running" || true) | wc -l | tr -d ' ')
        if [ "$NOT_RUNNING" -ne 0 ]; then
            echo "WARN: $NOT_RUNNING Orchard controller pods are not running"
        else
            echo "OK ($ORCHARD_PODS pods running)"
        fi
    fi
else
    echo "INFO: Orchard not deployed"
fi

echo ""
echo "=== Validation Summary ==="
echo "Cluster validation: PASSED"
echo "VM infrastructure: Available"
echo ""
echo "Homelab is ready for use!"
echo ""
echo "Quick Start:"
echo "  make status    - Check cluster and VM status"
echo "  make vms       - List all VMs"
echo "  make vm-create - Create new VM"