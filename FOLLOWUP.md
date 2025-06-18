# Followup Tasks and Recommendations

## Host Monitoring (External Hosts)

### Recommended Approach: osquery + osquery_exporter + Prometheus
For monitoring external hosts outside the Kubernetes cluster:

**Setup:**
- Deploy osquery daemon on each external host
- Use osquery_exporter to convert osquery tables to Prometheus metrics
- Configure Prometheus in the cluster to scrape from external hosts
- Leverage existing Grafana for visualization

**Benefits:**
- SQL-like queries for rich system data (processes, network connections, files, users, etc.)
- Flexible custom monitoring queries beyond standard metrics
- Integrates seamlessly with existing Prometheus/Grafana stack
- Excellent for both system monitoring and security use cases
- More powerful than standard node_exporter

**Alternative:** 
Standard node_exporter for basic system metrics (simpler setup but less flexible)

**Implementation Priority:** Medium - Should be added after core cluster stability is achieved

## Let's Encrypt TLS Setup

### Current Status - DNS-01 Challenge Implementation
- **DNS Provider:** ✅ NS1 (dns1.p07.nsone.net) identified and confirmed working
- **Cert-manager:** ✅ Installed and running with external DNS servers (8.8.8.8, 1.1.1.1)
- **NS1 Webhook:** ✅ Installed via Helm (`cert-manager-webhook-ns1`)
- **API Access:** ✅ NS1 API working perfectly (manual TXT record creation/deletion verified)
- **ClusterIssuers:** ✅ Configured for both staging (`letsencrypt-dns01-staging`) and production (`letsencrypt-dns01-prod`)
- **API Credentials:** ✅ NS1 API key stored in Kubernetes secret `ns1-credentials`

### Issue Identified
**Problem:** Cert-manager challenge fails at DNS verification stage
- Challenge gets created but webhook isn't being triggered to create TXT records
- Error: "Could not find the SOA record in the DNS tree for the domain '_acme-challenge.megalopolis.iaconelli.org.'"
- This suggests cert-manager is looking for the TXT record before the webhook creates it

### Infrastructure Components Working
```yaml
# ClusterIssuer configuration (working)
groupName: acme.nsone.net
solverName: ns1
endpoint: https://api.nsone.net/v1/
apiKeySecretRef: ns1-credentials/apiKey
```

### Next Steps for DNS-01 Let's Encrypt

**Immediate Debugging Steps:**
1. **Restart cert-manager:** `kubectl rollout restart deployment/cert-manager -n cert-manager`
2. **Check webhook connectivity:** `kubectl exec -n cert-manager deployment/cert-manager -- curl -k https://cert-manager-webhook-ns1.cert-manager.svc:443/`
3. **Verify API service:** `kubectl get apiservices v1alpha1.acme.nsone.net -o yaml`
4. **Test webhook directly:** Try calling the webhook API manually
5. **Check RBAC permissions:** Ensure cert-manager can call the webhook

**Alternative Approach:**
- Try different webhook implementation (orb-community/cert-manager-webhook-ns1)
- Fall back to HTTP-01 with tunnel solution (ngrok, Cloudflare Tunnel)
- Use DNS-01 with different provider (Cloudflare, Route53)

**Long-term:**
1. **Test with production issuer** - Once staging works, switch to production
2. **Certificate automation** - Create ingress with automatic certificate provisioning
3. **Monitoring** - Set up certificate expiration monitoring

**Automation & CI/CD:**
1. **GitHub Secrets Setup:**
   ```bash
   # Add to GitHub repository secrets:
   NS1_API_KEY=YOUR_NS1_API_KEY
   ```

2. **Bootstrap Script Enhancement:**
   ```bash
   # Add to scripts/bootstrap.sh:
   if [ -n "$NS1_API_KEY" ]; then
     kubectl create secret generic ns1-credentials \
       --from-literal=apiKey="$NS1_API_KEY" \
       -n cert-manager
   fi
   ```

3. **CI/CD Pipeline Integration:**
   ```yaml
   # .github/workflows/deploy.yml
   - name: Setup Let's Encrypt DNS-01
     env:
       NS1_API_KEY: ${{ secrets.NS1_API_KEY }}
     run: |
       helm install cert-manager-webhook-ns1 cert-manager-webhook-ns1/cert-manager-webhook-ns1 --namespace cert-manager
       kubectl create secret generic ns1-credentials --from-literal=apiKey="$NS1_API_KEY" -n cert-manager
       kubectl apply -f k8s-manifests/letsencrypt-dns01-issuer.yaml
   ```

**Security Considerations:**
1. **API Key Rotation:** Rotate NS1 API key after initial setup
2. **Least Privilege:** Ensure NS1 API key has minimal required permissions  
3. **Secret Management:** Consider external secret management (External Secrets Operator with NS1)
4. **API Key Security:** API key removed from documentation and cluster for security

### Immediate Setup for GitHub Secrets

**Right Now:**
1. **Add to GitHub Secrets:**
   - Go to repository Settings → Secrets and variables → Actions
   - Add secret: `NS1_API_KEY` = `YOUR_NS1_API_KEY`

2. **Test Automated Bootstrap:**
   ```bash
   # Delete current cluster and test automated deployment
   make clean
   export NS1_API_KEY="YOUR_NS1_API_KEY"
   make init
   ```

3. **Rotate API Key:**
   - Generate new API key in NS1 portal
   - Update GitHub secret
   - Update cluster: `kubectl create secret generic ns1-credentials --from-literal=apiKey="NEW_KEY" -n cert-manager --dry-run=client -o yaml | kubectl apply -f -`

### Alternative: Fallback to Self-Signed
- Self-signed certificates via `selfsigned-issuer` ClusterIssuer ✅
- Works perfectly for local development and testing
- Already deployed and functional

## Additional Configuration & Operational Notes

### Current Lab Architecture Status
**Strengths:**
- **Multi-service deployment:** Core services (ArgoCD, monitoring, keycloak, external-secrets) integrated into bootstrap
- **VM management:** Orchard controller working, VMs accessible via API
- **Dashboard:** Real-time status monitoring with proper service health checks
- **Infrastructure as Code:** All configurations in Git, reproducible deployments

**Areas for Improvement:**
- **Certificate automation:** DNS-01 challenge needs debugging (webhook communication issue)
- **Missing services deployment:** Several services show "namespace ready" but not fully deployed
- **Monitoring gaps:** Prometheus/Grafana installed but not fully configured
- **Documentation:** Need operational runbooks for common tasks

### DNS & Networking Configuration
**Current State:**
- `megalopolis.iaconelli.org` → `154.61.56.34` (external server)
- Local cluster accessible via Kind port-forwarding
- ingress-nginx installed and working for internal routing

**Future Considerations:**
1. **Public access:** If you want external access to services:
   - Set up reverse proxy/tunnel (ngrok, Cloudflare Tunnel)
   - Configure proper DNS routing to your public IP
   - Implement proper authentication/authorization

2. **Internal DNS:** Consider setting up internal DNS for service discovery:
   - CoreDNS customization for local domains
   - Service mesh (Istio/Linkerd) for advanced traffic management

### Service Dependencies & Startup Order
**Critical Path:**
1. cert-manager (for TLS)
2. ingress-nginx (for routing)  
3. external-secrets (for credential management)
4. monitoring stack (for observability)
5. application services (ArgoCD, etc.)

**Missing Startup Coordination:**
- No wait conditions between services
- Services may start before dependencies are ready
- Consider using Helm hooks or init containers for proper ordering

### Resource Management & Scaling
**Current Allocation:**
- 128GB RAM, 24 cores available
- Kind cluster: ~8GB allocated to 4 nodes
- VM overhead: ~20GB for running VMs
- Remaining: ~100GB for applications

**Optimization Opportunities:**
1. **Resource requests/limits:** Most services don't have proper resource constraints
2. **Node affinity:** Could optimize placement for VM vs application workloads
3. **Horizontal Pod Autoscaling:** Not configured for any services
4. **Persistent storage:** Using emptyDir, consider persistent volumes for data

### Monitoring & Alerting Strategy
**Current Gaps:**
1. **No alerts configured:** Prometheus installed but no AlertManager rules
2. **No log aggregation:** Consider ELK/Loki stack for centralized logging
3. **No distributed tracing:** Could add Jaeger/Zipkin for complex debugging
4. **Certificate expiration monitoring:** Need alerts before certificates expire

**Recommended Additions:**
```yaml
# Add to monitoring stack
- AlertManager with Slack/email notifications
- Grafana dashboards for:
  - Cluster resource usage
  - Application performance  
  - Certificate expiration dates
  - VM health and performance
```

### Backup & Disaster Recovery
**Currently Missing:**
1. **Persistent data backup:** No backup strategy for:
   - ArgoCD configuration
   - Monitoring data (Prometheus)
   - VM disk images
   - Kubernetes etcd

2. **Recovery procedures:** No documented process for:
   - Cluster rebuild from backup
   - Service restoration priority
   - Data migration procedures

**Recommended Implementation:**
```bash
# Add to scripts/
backup-cluster.sh    # Backup etcd, persistent volumes, configs
restore-cluster.sh   # Restore from backup
disaster-recovery.md # Step-by-step recovery procedures
```

### Security Hardening Checklist
**Network Security:**
- [ ] Network policies for pod-to-pod communication
- [ ] Ingress TLS termination (pending DNS-01 fix)
- [ ] Service mesh for mTLS (optional)

**Access Control:**
- [ ] RBAC policies review (currently using default service accounts)
- [ ] Pod Security Standards enforcement
- [ ] Secrets rotation automation

**Image Security:**
- [ ] Container image scanning
- [ ] Non-root user enforcement
- [ ] Read-only root filesystems where possible

### Development Workflow Integration
**Current State:**
- Manual deployment via `make init`
- No CI/CD pipeline active
- Configuration drift possible

**Recommended Additions:**
1. **Pre-commit hooks:** Validate YAML, run security scans
2. **Automated testing:** Integration tests for each service
3. **GitOps workflow:** ArgoCD managing itself + applications
4. **Environment promotion:** Staging → Production deployment pipeline

### Maintenance & Operations
**Regular Tasks Needed:**
1. **Weekly:**
   - Check certificate expiration dates
   - Review resource usage and scaling needs
   - Update service configurations

2. **Monthly:**
   - Rotate API keys and credentials
   - Update container images
   - Review and update monitoring dashboards

3. **Quarterly:**
   - Kubernetes version upgrade
   - Security audit and penetration testing
   - Disaster recovery testing

**Automation Opportunities:**
```bash
# Add to scripts/
maintenance/
├── cert-expiry-check.sh
├── resource-cleanup.sh  
├── security-scan.sh
└── health-check.sh
```

### Integration Points for External Systems
**Current Integrations:**
- NS1 DNS for domain management
- GitHub for code repository
- Docker Hub for container images

**Future Integration Candidates:**
- **Identity Provider:** Keycloak integration with external LDAP/SAML
- **Secret Management:** External Secrets with AWS/Azure/Vault
- **Monitoring:** Integration with external monitoring (DataDog, New Relic)
- **Backup Storage:** S3/Azure Blob for automated backups

### Lessons Learned & Quick Wins

**What Worked Well:**
1. **Kind for local development:** Stable, fast cluster creation/destruction
2. **Helm for service management:** Easy to install complex applications
3. **Comprehensive status dashboard:** Real-time visibility into all services
4. **Modular architecture:** Each service independently deployable and testable
5. **Configuration as code:** Everything in Git, reproducible deployments

**Pain Points Encountered:**
1. **Docker image availability:** Local images need manual loading into Kind
2. **Service startup dependencies:** No coordination, services start regardless of dependencies
3. **DNS resolution in cluster:** Internal DNS causes issues with external DNS validation
4. **Webhook debugging:** Limited logging/visibility into webhook interactions
5. **Certificate complexity:** Multiple moving parts (cert-manager, webhook, DNS, ACME)

**Immediate Quick Wins (Low Effort, High Impact):**
1. **Resource limits:** Add memory/CPU limits to prevent resource exhaustion
2. **Readiness probes:** Fix services that show "not ready" due to health check issues
3. **Persistent volumes:** Replace emptyDir with persistent storage for data retention
4. **Service monitors:** Add Prometheus ServiceMonitor resources for better metrics
5. **Dashboard automation:** Auto-refresh status data instead of manual updates

**Architecture Decisions to Revisit:**
1. **Monolithic bootstrap:** Consider splitting into modular components
2. **Local vs remote deployment:** Clear strategy for local dev vs production
3. **Secret management:** Move from manual secrets to automated External Secrets
4. **Service mesh:** Evaluate if traffic management complexity justifies service mesh
5. **Multi-cluster:** Consider if workload separation (dev/staging/prod) needs separate clusters

### Technical Debt Inventory
**High Priority:**
- DNS-01 webhook communication issue (blocks automated TLS)
- Missing service deployments (monitoring stack not fully functional)
- No backup/restore procedures (data loss risk)

**Medium Priority:**
- Resource constraints not defined (potential resource contention)
- No alerting configured (operational blind spots)
- Manual secret management (security and automation concerns)

**Low Priority:**
- Service startup coordination (mostly cosmetic, services eventually work)
- Container image optimization (performance, not functionality)
- Advanced networking features (nice-to-have)

### Success Metrics & KPIs
**Current Measurable Outcomes:**
- ✅ **Cluster bootstrap time:** ~5 minutes for full deployment
- ✅ **Service availability:** 23/26 pods running (89% success rate)
- ✅ **VM management:** 2/4 VMs operational with API access
- ✅ **Dashboard visibility:** Real-time status for 14 service components

**Target Improvements:**
- 🎯 **Bootstrap automation:** 0 manual steps with GitHub secrets
- 🎯 **Service reliability:** 100% of intended services operational
- 🎯 **Certificate automation:** 0 manual certificate management
- 🎯 **Monitoring coverage:** Alerts for all critical service failures

This homelab represents a solid foundation for learning Kubernetes, GitOps, and cloud-native technologies. The investment in automation and infrastructure-as-code will pay dividends as complexity grows.

## Other Followup Items

### VM Monitoring
- Implement comprehensive VM health monitoring
- Add VM resource usage tracking (CPU, memory, disk)
- Set up alerts for VM failures or resource exhaustion
- Consider implementing VM auto-restart capabilities

### Cluster Monitoring
- Complete Prometheus/Grafana deployment (currently in bootstrap but not yet run)
- Add custom dashboards for homelab-specific metrics
- Implement alerting for critical cluster events
- Monitor ArgoCD application health and sync status

### Security
- Implement proper TLS certificates (currently using self-signed)
- Set up proper authentication/authorization
- Regular security updates and patching