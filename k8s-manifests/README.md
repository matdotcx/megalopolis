# Kubernetes VM Operator Deployment

This directory contains Kubernetes manifests for deploying the Minimal VM Operator to provide HTTP API access to VM management functionality.

## Files

- `vm-operator-deployment.yaml` - Deployment, ServiceAccount, and RBAC configuration
- `vm-operator-service.yaml` - Service and Ingress configuration

## Requirements

### Cluster Requirements

**✅ Working Environments:**
- **Real Kubernetes clusters** (cloud providers, bare metal)
- **Kubernetes on Docker** with host filesystem access
- **Minikube** with hostPath volumes enabled
- **K3s** on physical hosts

**❌ Limited/Non-Working Environments:**
- **Kind clusters** - No host filesystem access
- **CodeSpaces/GitPod** - Isolated container environments  
- **CI/CD Kubernetes** - No access to host VM storage

### Host Requirements

1. **Tart Binary Access**
   ```bash
   # Binary must be accessible at the configured hostPath
   # Default: /Users/diego/Developer/workspace/matdotcx/megalopolis/tart-binary
   ls -la /path/to/tart-binary
   ```

2. **VM Storage Directory**
   ```bash
   # VM storage must exist and be writable
   # Default: /Users/diego/.tart
   ls -la ~/.tart/
   ```

3. **Node Compatibility**
   - Linux nodes (containers run Linux regardless of host OS)
   - Proper permissions for hostPath volume mounts
   - Network access for pod-to-host communication

## Configuration

### HostPath Volume Configuration

The deployment uses hostPath volumes to access host resources:

```yaml
volumes:
- name: tart-binary
  hostPath:
    path: /Users/diego/Developer/workspace/matdotcx/megalopolis/tart-binary
    type: File
- name: tart-storage
  hostPath:
    path: /Users/diego/.tart
    type: DirectoryOrCreate
```

**Important:** Update these paths to match your environment before deployment.

### Resource Limits

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```

### Security Context

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
```

## Deployment

### Quick Start

```bash
# Deploy VM operator
kubectl apply -f vm-operator-deployment.yaml
kubectl apply -f vm-operator-service.yaml

# Check deployment status
kubectl get pods -n orchard-system
kubectl get svc -n orchard-system

# Test the API
kubectl port-forward -n orchard-system svc/vm-operator 8082:8082
curl http://localhost:8082/health
```

### Verification

```bash
# Check pod status
kubectl describe pod -n orchard-system -l app=vm-operator

# Check logs
kubectl logs -n orchard-system -l app=vm-operator

# Test API endpoints
kubectl port-forward -n orchard-system svc/vm-operator 8082:8082 &
curl http://localhost:8082/health
curl http://localhost:8082/vms
```

## Known Issues and Limitations

### HostPath Volume Limitations

**Issue:** Pods remain in `Pending` state with volume mount errors

**Cause:** HostPath volumes require:
- Files/directories to exist on the host
- Proper file permissions
- Host filesystem accessible to Kubernetes nodes

**Solutions:**
1. **Update paths** in deployment manifest to match your environment
2. **Ensure permissions** allow container user (UID 1000) to access files
3. **Create directories** if they don't exist:
   ```bash
   mkdir -p ~/.tart
   chmod 755 ~/.tart
   ```

### Container Image Availability

**Issue:** `ImagePullBackOff` or `ErrImagePull`

**Cause:** Image not available in cluster

**Solutions:**
1. **For Kind clusters:**
   ```bash
   # Build and load image
   docker build -t megalopolis/vm-operator:latest -f docker/vm-operator/Dockerfile .
   kind load docker-image megalopolis/vm-operator:latest
   ```

2. **For other clusters:**
   ```bash
   # Push to registry or ensure image is available
   docker build -t your-registry/vm-operator:latest .
   docker push your-registry/vm-operator:latest
   ```

### Network Access Issues

**Issue:** API not accessible via service

**Solutions:**
1. **Check service configuration:**
   ```bash
   kubectl get svc -n orchard-system vm-operator
   ```

2. **Use port-forwarding for testing:**
   ```bash
   kubectl port-forward -n orchard-system svc/vm-operator 8082:8082
   ```

3. **Check ingress controller** (if using ingress)

## Testing

Run the Kubernetes-specific test suite:

```bash
# Test K8s deployment
bash tests/test-k8s-vm-operator.sh

# Test integration
bash tests/test-vm-operator-integration.sh
```

**Expected Results:**
- ✅ Manifests are valid
- ✅ RBAC resources created successfully  
- ✅ Service endpoints configured correctly
- ❌ Pod may fail to start due to hostPath volume issues in some environments

## Troubleshooting

### Pod Stuck in Pending

```bash
# Check events for scheduling issues
kubectl describe pod -n orchard-system -l app=vm-operator

# Common issues:
# 1. Node selector doesn't match any nodes
# 2. HostPath volumes don't exist
# 3. Resource constraints
```

### Pod CrashLoopBackOff

```bash
# Check container logs
kubectl logs -n orchard-system -l app=vm-operator

# Common issues:
# 1. Tart binary not executable
# 2. Permission denied on VM storage
# 3. Python import errors
```

### API Not Responding

```bash
# Test pod health directly
kubectl exec -n orchard-system -l app=vm-operator -- python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8082/health').read().decode())"

# Check service endpoints
kubectl get endpoints -n orchard-system vm-operator

# Test with port forwarding
kubectl port-forward -n orchard-system svc/vm-operator 8082:8082
curl http://localhost:8082/health
```

## Alternative Deployment Patterns

### For Kind/Containerized Clusters

Consider using init containers or sidecar patterns instead of hostPath volumes:

```yaml
# Example: Init container to copy tart binary
initContainers:
- name: setup-tart
  image: alpine
  command: ['sh', '-c', 'cp /host-tart/tart-binary /shared/tart-binary && chmod +x /shared/tart-binary']
  volumeMounts:
  - name: shared-bin
    mountPath: /shared
  - name: host-tart
    mountPath: /host-tart
```

### For CI/CD Environments

Use CLI management instead of containerized VM operator:

```bash
# Direct VM management
./scripts/setup-vms.sh list
./scripts/setup-vms.sh start vm-name
./scripts/setup-vms.sh stop vm-name
```

## Production Considerations

1. **Resource Scaling:** Adjust CPU/memory limits based on VM count
2. **High Availability:** Consider multiple replicas with leader election
3. **Monitoring:** Add Prometheus metrics and health monitoring
4. **Security:** Review RBAC permissions and network policies
5. **Backup:** Ensure VM storage is properly backed up