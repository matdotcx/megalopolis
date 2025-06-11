#!/bin/bash
set -euo pipefail

# Use project-local binaries
KUBECTL="./kubectl"

echo "Validating cluster health..."

# Check if cluster exists
if ! $KUBECTL cluster-info &>/dev/null; then
    echo "ERROR: Cluster is not accessible"
    exit 1
fi

# Check nodes
echo -n "Checking nodes... "
NODE_COUNT=$($KUBECTL get nodes --no-headers | wc -l | tr -d ' ')
if [ "$NODE_COUNT" -ne 3 ]; then
    echo "FAIL: Expected 3 nodes, found $NODE_COUNT"
    exit 1
else
    echo "OK (3 nodes)"
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

echo ""
echo "Cluster validation: PASSED"
echo ""
echo "Cluster is ready for use!"