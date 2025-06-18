# Dashboard Fix Plan - Get Everything Green

## Current Context

**Date:** 2025-06-17  
**Branch:** feature/minimal-vm-operator  
**Dashboard URL:** http://localhost:8090  
**Status:** Multiple services failing (red) and incomplete (yellow)

### Current Dashboard Status Analysis

**✅ GREEN (Working - 6 services):**
- Docker - Container runtime healthy
- Kind - Kubernetes cluster running
- kubectl - Client connectivity working
- Tart - VM management binary functional
- ArgoCD - 7 pods running successfully
- Network - Docker networking operational

**⚠️ YELLOW/WARNING (Partial - 5 services):**
- cert-manager - Namespace exists but no pods deployed
- ingress-nginx - Namespace exists but no pods deployed  
- external-secrets - Namespace exists but no pods deployed
- monitoring - Namespace exists but no pods deployed
- keycloak - Namespace exists but no pods deployed

**❌ RED/FAILING (Broken - 4 services):**
- orchard-system - 0/3 pods running (CrashLoopBackOff + ContainerCreating)
- macos-dev VM - Not found/not created
- macos-ci VM - Not found/not created
- total-vms - 0 running VMs

### Root Cause Analysis

1. **orchard-system issues:**
   - `vm-api-bridge` in CrashLoopBackOff (legacy component)
   - `vm-operator` pods stuck in ContainerCreating (hostPath volume mount issues)
   - Running in Kind cluster where hostPath volumes don't work

2. **VM issues:**
   - VMs were never created from base images
   - Need to pull and configure macos-dev and macos-ci

3. **K8s services:**
   - Namespaces created but actual services never deployed
   - Need to deploy the actual controllers/operators

## Action Plan

### Phase 1: Fix VM Operator (HIGH PRIORITY)
**Goal:** Get orchard-system from RED to GREEN

1. **Clean up broken deployments**
   ```bash
   # Remove legacy vm-api-bridge that's crashing
   kubectl delete deployment vm-api-bridge -n orchard-system --ignore-not-found
   
   # Remove broken vm-operator deployments with hostPath issues
   kubectl delete deployment vm-operator -n orchard-system --ignore-not-found
   kubectl delete pods -n orchard-system --all
   ```

2. **Deploy working VM operator**
   ```bash
   # Use the tested minimal VM operator without hostPath volumes for Kind
   # Create a Kind-compatible deployment
   kubectl apply -f k8s-manifests/vm-operator-deployment-kind.yaml
   kubectl apply -f k8s-manifests/vm-operator-service.yaml
   ```

3. **Alternative: Use CLI management**
   ```bash
   # If K8s deployment continues to fail in Kind, document that orchard-system
   # should show "CLI management active" instead of pod-based management
   ```

### Phase 2: Create and Start VMs (HIGH PRIORITY)  
**Goal:** Get VM status from RED to GREEN

1. **Create VMs from base images**
   ```bash
   # Clone base images to create named VMs
   ./tart-binary clone ghcr.io/cirruslabs/macos-sequoia-base:latest macos-dev
   ./tart-binary clone ghcr.io/cirruslabs/macos-sequoia-base:latest macos-ci
   
   # Verify VMs exist
   ./tart-binary list
   ```

2. **Start VMs**
   ```bash
   # Start development VM
   ./tart-binary run macos-dev --no-graphics &
   
   # Start CI VM  
   ./tart-binary run macos-ci --no-graphics &
   
   # Wait for VMs to be ready
   bash scripts/vm-readiness-monitor.sh wait macos-dev
   bash scripts/vm-readiness-monitor.sh wait macos-ci
   ```

### Phase 3: Deploy Missing K8s Services (MEDIUM PRIORITY)
**Goal:** Get support services from YELLOW to GREEN

1. **Deploy cert-manager**
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
   
   # Wait for pods to be ready
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
   ```

2. **Deploy ingress-nginx**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/kind/deploy.yaml
   
   # Wait for controller to be ready
   kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
   ```

3. **Deploy external-secrets (optional)**
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets
   ```

4. **Deploy monitoring stack (optional)**
   ```bash
   # Prometheus operator
   kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml
   ```

### Phase 4: Validation
**Goal:** Verify dashboard shows all green

1. **Check dashboard status**
   ```bash
   curl -s http://localhost:8090/api/status | python3 -m json.tool
   ```

2. **Expected final status:**
   - **15 GREEN** services
   - **0 YELLOW** warnings
   - **0 RED** failures

## Implementation Notes

### Kind Cluster Limitations
- hostPath volumes don't work (no host filesystem access)
- Need to use alternative deployment patterns for VM operator
- Consider using init containers or configMaps instead of direct file mounts

### VM Creation Requirements
- Requires authentication to ghcr.io/cirruslabs for image pulls
- VMs need significant resources (4GB+ RAM each)
- Starting VMs may take 5-10 minutes to fully boot

### Testing Strategy
After each phase:
```bash
# Test dashboard API
curl -s http://localhost:8090/api/status

# Test VM operator if deployed
curl -s http://localhost:8082/health

# Test VMs directly
./tart-binary list
bash scripts/vm-readiness-monitor.sh check macos-dev
```

## Success Criteria

**Phase 1 Complete:** orchard-system shows 1+ running pods OR "CLI management active"
**Phase 2 Complete:** macos-dev and macos-ci show "ready" status, total-vms shows "2 running"  
**Phase 3 Complete:** All support services show "healthy" with pod counts
**Phase 4 Complete:** Dashboard summary shows 15 green, 0 yellow, 0 red

## Rollback Plan

If any phase fails:
1. Document the specific failure in TROUBLESHOOTING.md
2. Use CLI management as fallback for VM operations
3. Keep services that work, document limitations for services that don't
4. Update dashboard to show "expected limitations in Kind environment"

## Context for Future Development

This plan addresses the immediate dashboard health issues but also identifies that some components (like VM operator with hostPath volumes) have fundamental limitations in containerized K8s environments. The comprehensive testing and documentation we created earlier provides the foundation for understanding these limitations and implementing appropriate workarounds.