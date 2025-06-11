#!/bin/bash
set -euo pipefail

KIND="./kind-binary"
KUBECTL="./kubectl"
CLUSTER_NAME="homelab"

# Check if cluster exists
if $KIND get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    
    # Check if it's healthy
    if $KUBECTL cluster-info &>/dev/null; then
        # Check if ArgoCD is installed
        if $KUBECTL get namespace argocd &>/dev/null; then
            echo "ArgoCD is already installed."
            echo ""
            echo "Your homelab is already set up!"
            echo "Run 'make status' to check the status."
            echo "Run 'make rebuild' if you want to start fresh."
            # Exit 0 means "already set up, no action needed"
            exit 0
        else
            echo "Cluster exists but ArgoCD is not installed."
            echo "Continuing with bootstrap..."
            # Exit 2 means "cluster exists but needs bootstrap"
            exit 2
        fi
    else
        echo "Cluster exists but is not healthy."
        echo "Run 'make rebuild' to recreate it."
        # Exit 1 means "error state"
        exit 1
    fi
else
    # Cluster doesn't exist, that's fine for init
    # Exit 3 means "cluster doesn't exist, proceed with full setup"
    exit 3
fi