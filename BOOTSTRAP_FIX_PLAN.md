# Bootstrap Fix Plan - ArgoCD Deployment Reliability

**Date**: June 19, 2025  
**Status**: Approved plan, ready for implementation  
**Context**: Fixing silent ArgoCD deployment failures in `make clean && make init` automation

## Background Context

### **Current Problem**
- `make clean && make init` automation partially fails
- ArgoCD services/RBAC created but **zero pods deployed**
- Silent failure - no obvious error messages
- Bootstrap script completes successfully but system non-functional
- VM automation works perfectly, Kubernetes service deployment broken

### **Root Cause Analysis Completed**
- Large ArgoCD manifest (600+ lines) partially applies
- CRDs, ServiceAccounts, Services created successfully  
- **Deployments and StatefulSets NOT created** (critical failure)
- No network errors, no kubectl errors, **silent partial application**
- Same pattern likely affects cert-manager and ingress-nginx

### **Test Results from June 19, 2025**
```bash
# What works:
kubectl get services -n argocd        # ✅ 4 services
kubectl get crds | grep argocd        # ✅ 3 CRDs
kubectl get configmaps -n argocd      # ✅ Multiple configs

# What fails:
kubectl get deployments -n argocd     # ❌ No resources found  
kubectl get statefulsets -n argocd    # ❌ No resources found
kubectl get pods -n argocd            # ❌ No resources found
```

## Approved Implementation Plan

### **Approach Decisions Made**
1. **Stick with manifest approach** - Helm adds unnecessary complexity
2. **Retry logic**: 3 retries with 10-second delays  
3. **Chunked deployment**: ArgoCD only for now
4. **Logging level**: Debug for implementation, Info for production
5. **Scope**: Focus on ArgoCD first, apply lessons to other services later
6. **Failure handling**: Continue on partial failures, don't fail fast
7. **Recovery**: Add retry and better error reporting (automatic recovery not required)
8. **Success criteria**: 100% of clean deploys should work
9. **Bootstrap time**: Longer acceptable for reliability

### **Core Strategy: Chunked Deployment with Retries**

**Split ArgoCD manifest into logical chunks:**
- **Chunk 1**: CRDs only
- **Chunk 2**: RBAC (ServiceAccounts, Roles, Bindings)  
- **Chunk 3**: ConfigMaps and Secrets
- **Chunk 4**: Services
- **Chunk 5**: Deployments and StatefulSets (the failing part)

**Add wait conditions and health checks between chunks**

## Detailed Implementation TODO

### **Phase 1: Debug Current Failure (30 minutes)**
1. **Add comprehensive logging to `scripts/bootstrap.sh`**
   ```bash
   # Add debug logging function
   log_debug() { echo "[DEBUG $(date '+%H:%M:%S')] $*"; }
   
   # Log every kubectl command with output
   log_debug "Applying ArgoCD manifest..."
   kubectl apply -n argocd -f https://... 2>&1 | tee -a /tmp/bootstrap.log
   ```

2. **Test ArgoCD deployment in isolation**
   - Download manifest to local file first
   - Test kubectl apply with full manifest  
   - Use `kubectl apply --dry-run=server` to validate
   - Count resources before/after application

### **Phase 2: Implement Chunked ArgoCD Deployment (45 minutes)**
3. **Create manifest chunking function in `scripts/bootstrap.sh`**
   ```bash
   deploy_argocd_chunked() {
       local manifest_url="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
       local temp_file="/tmp/argocd-manifest.yaml"
       
       # Download and verify manifest
       curl -sSL "$manifest_url" > "$temp_file"
       log_debug "Downloaded ArgoCD manifest: $(wc -l < "$temp_file") lines"
       
       # Apply in chunks with verification
       apply_chunk "CRDs" "kind: CustomResourceDefinition"
       apply_chunk "RBAC" "kind: ServiceAccount\|kind: Role\|kind: ClusterRole\|kind: RoleBinding\|kind: ClusterRoleBinding"
       apply_chunk "ConfigMaps" "kind: ConfigMap"  
       apply_chunk "Secrets" "kind: Secret"
       apply_chunk "Services" "kind: Service"
       apply_chunk "Deployments" "kind: Deployment\|kind: StatefulSet"
   }
   ```

4. **Implement `apply_chunk()` function with retries**
   ```bash
   apply_chunk() {
       local chunk_name="$1"
       local resource_pattern="$2"
       
       log_debug "Applying $chunk_name chunk..."
       
       # Extract chunk from manifest
       grep -A 100 "$resource_pattern" "$temp_file" | split_yaml_resources > "/tmp/chunk_${chunk_name}.yaml"
       
       # Apply with retries
       for attempt in 1 2 3; do
           if kubectl apply -n argocd -f "/tmp/chunk_${chunk_name}.yaml" 2>&1 | tee -a /tmp/bootstrap.log; then
               log_debug "$chunk_name applied successfully on attempt $attempt"
               break
           else
               log_debug "$chunk_name failed on attempt $attempt, retrying in 10s..."
               sleep 10
           fi
       done
       
       # Verify chunk deployment
       verify_chunk_success "$chunk_name"
   }
   ```

### **Phase 3: Add Wait Conditions and Health Checks (45 minutes)**
5. **Add proper wait conditions between chunks**
   ```bash
   # After CRDs
   kubectl wait --for condition=established --timeout=60s crd/applications.argoproj.io
   
   # After Deployments  
   kubectl wait --for=condition=Ready pods -n argocd -l app.kubernetes.io/name=argocd-server --timeout=300s
   ```

6. **Implement comprehensive ArgoCD health verification**
   ```bash
   verify_argocd_health() {
       log_debug "Verifying ArgoCD deployment health..."
       
       # Check expected resource counts
       local expected_pods=7
       local actual_pods=$(kubectl get pods -n argocd --no-headers | grep Running | wc -l)
       
       if [ "$actual_pods" -eq "$expected_pods" ]; then
           log_debug "✅ ArgoCD health check passed: $actual_pods/$expected_pods pods running"
           return 0
       else
           log_debug "⚠️ ArgoCD health check failed: $actual_pods/$expected_pods pods running"
           return 1
       fi
   }
   ```

### **Phase 4: Integration and Testing (30 minutes)**
7. **Update `scripts/bootstrap.sh` to use chunked deployment**
   - Replace single ArgoCD kubectl apply with `deploy_argocd_chunked`
   - Add health verification after ArgoCD
   - Continue bootstrap even if ArgoCD partially fails

8. **Enhance `scripts/validate-deployment.sh`**
   - Add detailed ArgoCD pod counting and status checks
   - Verify ArgoCD server accessibility  
   - Test ArgoCD admin password retrieval

## Files That Will Be Modified

### **Primary: `scripts/bootstrap.sh`**
- Add debug logging infrastructure
- Replace ArgoCD installation section with chunked deployment
- Add retry logic and health checks
- Improve error handling and reporting

### **Secondary: `scripts/validate-deployment.sh`**  
- Add comprehensive ArgoCD validation
- Verify expected pod counts and readiness
- Test ArgoCD API accessibility

### **New Temporary Files Created During Bootstrap**
- `/tmp/argocd-manifest.yaml` - Downloaded manifest
- `/tmp/chunk_*.yaml` - Individual resource chunks
- `/tmp/bootstrap.log` - Detailed deployment logs

## Success Criteria

### **Functional Requirements**
- ✅ ArgoCD deployment succeeds in 100% of clean rebuilds
- ✅ All 7 ArgoCD pods reach Running state within 5 minutes  
- ✅ ArgoCD server becomes accessible and responsive
- ✅ Bootstrap continues even if ArgoCD has partial issues

### **Operational Requirements**  
- ✅ Clear debug logs show exactly what succeeded/failed
- ✅ Retry logic handles transient network/API issues
- ✅ Health checks verify deployment before proceeding
- ✅ User gets clear status of deployment progress

### **Testing Requirements**
- ✅ Multiple `make clean && make init` cycles succeed consistently
- ✅ Dashboard shows ArgoCD as healthy after bootstrap
- ✅ ArgoCD admin password accessible via kubectl
- ✅ No silent failures or partial deployments

## Context for Future Sessions

### **Current System State (as of June 19, 2025)**
- **Cluster**: 4-node Kind cluster operational
- **VMs**: macos-dev and macos-ci running (VM automation works perfectly)
- **ArgoCD**: Partially deployed (services yes, pods no) 
- **cert-manager**: Status unknown, likely same issue
- **ingress-nginx**: Status unknown, likely same issue
- **Dashboard**: Working but shows failures due to missing services

### **Next Steps After ArgoCD Fix**
1. Apply same chunked deployment pattern to cert-manager
2. Apply same pattern to ingress-nginx  
3. Test complete automation reliability
4. Update documentation with new deployment patterns

### **Key Insights Discovered**
- **VM automation is production-ready** - no changes needed
- **Large manifest application is unreliable** - needs chunking
- **Silent failures mask real problems** - need explicit verification
- **Bootstrap script needs better error handling** - continue-on-failure approach

### **Technical Notes**
- ArgoCD manifest URL: `https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
- Expected ArgoCD pods: 7 (server, repo-server, dex, controller, etc.)
- Current functional components: Kind cluster, VM management, dashboard, basic networking
- Problem components: All Kubernetes application deployments

This plan provides a systematic approach to fixing the core automation reliability issue while maintaining the working components and not adding unnecessary complexity.