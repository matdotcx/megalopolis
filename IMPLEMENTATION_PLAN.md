# macOS Homelab Implementation Plan

## Project Overview

This document outlines the complete implementation plan for building a production-grade Kubernetes homelab on macOS using the Mac Studio (xenon). The goal is to create a fully automated, secure, and scalable development environment that can be rebuilt from scratch in under 5 minutes.

## Architecture Decisions

### Why Kind + Kubernetes?
- **Kind (Kubernetes in Docker)**: Lightweight, fast setup/teardown, excellent for development
- **Kubernetes**: Industry standard, GitOps-friendly, extensive ecosystem
- **macOS Native**: Leverages Docker Desktop, no virtualization overhead

### Why These Platform Choices?

1. **ArgoCD over Flux**: Better UI, easier debugging, more mature ecosystem
2. **NGINX Ingress over Apache**: Better Kubernetes integration, more features
3. **Keycloak over Kerberos**: Modern OIDC/SAML, web-native, easier to configure
4. **Cert-Manager**: De facto standard for Kubernetes certificate management
5. **External-DNS with NS1**: Full DNS automation, supports external access when needed
6. **Tailscale**: Zero-config VPN, secure remote access without port forwarding

## Infrastructure Architecture

```
┌─────────────────────────────────────────────────────────┐
│         NS1 DNS + External-DNS Operator                 │
│    (*.homelab.iaconelli.org - external when needed)    │
├─────────────────────────────────────────────────────────┤
│                    Tailscale VPN                        │
│         (Secure access from anywhere)                   │
├─────────────────────────────────────────────────────────┤
│                     Keycloak                            │
│              (SSO/OIDC Provider)                        │
├─────────────────────────────────────────────────────────┤
│   NGINX Ingress    │    Cert-Manager    │   CoreDNS    │
│  (Load Balancer)   │  (Let's Encrypt)   │  (Internal)  │
├─────────────────────────────────────────────────────────┤
│                     ArgoCD                              │
│              (GitOps Controller)                        │
├─────────────────────────────────────────────────────────┤
│  Prometheus  │  Grafana  │  Loki  │  External Secrets  │
├─────────────────────────────────────────────────────────┤
│              Kind Kubernetes Cluster                     │
│          (3 nodes: 1 control, 2 workers)               │
└─────────────────────────────────────────────────────────┘
```

## Critical Information

### Access Credentials
- **ArgoCD Admin Password**: `csDooGXxIKQ8c1Hf`
- **ArgoCD URL**: https://localhost:8080 (via port-forward)
- **Cluster Context**: `kind-homelab`

### Project Location
- **Path**: `~/homelab/` on xenon (Mac Studio)
- **Repository**: Git initialized with initial commit

### Tools Installed
- **kubectl**: v1.33.1 (downloaded to ~/homelab/)
- **helm**: v3.18.2 (downloaded to ~/homelab/)
- **kind**: v0.23.0 (downloaded as ~/homelab/kind-binary)

## Implementation Status

### Phase 1: Foundation ✅ COMPLETED
- [x] Created project structure at `~/homelab/`
- [x] Downloaded kubectl, helm, kind binaries
- [x] Created 3-node Kind cluster (1 control, 2 workers)
- [x] Set up Git repository with .gitignore
- [x] Created automation Makefile
- [x] Deployed ArgoCD successfully
- [x] Created bootstrap script

### Phase 2: Core Platform Services 📋 NEXT UP
**Objective**: Deploy essential platform infrastructure

1. **NGINX Ingress Controller**
   - Deploy via ArgoCD Application
   - Configure for Kind cluster
   - Set up port mappings (80, 443)

2. **Cert-Manager**
   - Install cert-manager operator
   - Configure Let's Encrypt ClusterIssuer
   - Set up local CA for development

3. **External Secrets Operator**
   - Deploy operator via ArgoCD
   - Configure SOPS provider
   - Generate age encryption keys

4. **SOPS Configuration**
   - Generate age keys for encryption
   - Configure .sops.yaml
   - Encrypt initial secrets

### Phase 3: Security & Authentication 📋 PENDING
1. **Keycloak for SSO**
2. **OAuth2-Proxy for app protection**
3. **Tailscale for secure remote access**

### Phase 4: Monitoring Stack 📋 PENDING
1. **Prometheus + Grafana**
2. **Loki for logging**
3. **Custom homelab dashboards**

### Phase 5: DNS & External Access 📋 PENDING
1. **External-DNS with NS1**
2. **Let's Encrypt automation**
3. **Domain: *.homelab.iaconelli.org**

### Phase 6: Applications 📋 PENDING
Priority apps: Homepage, ActualBudget, Excalidraw, Jellyfin, Paperless

## Quick Recovery Commands

```bash
# Access xenon
ssh xenon

# Navigate to project
cd ~/homelab

# Recreate cluster if needed
PATH="/usr/local/bin:$HOME/homelab:$PATH" ./kind-binary delete cluster --name homelab
PATH="/usr/local/bin:$HOME/homelab:$PATH" ./kind-binary create cluster --config kind/config-simple.yaml --name homelab

# Bootstrap ArgoCD
PATH="/usr/local/bin:$HOME/homelab:$PATH" ./scripts/bootstrap.sh

# Access ArgoCD UI
PATH="/usr/local/bin:$HOME/homelab:$PATH" ./kubectl port-forward -n argocd svc/argocd-server 8080:443
# Then visit: https://localhost:8080 (admin / csDooGXxIKQ8c1Hf)

# Check cluster status
PATH="/usr/local/bin:$HOME/homelab:$PATH" ./kubectl get nodes
PATH="/usr/local/bin:$HOME/homelab:$PATH" ./kubectl get pods -A
```

## Next Steps for Claude

1. **Create ArgoCD Applications**: Set up platform services as ArgoCD apps
2. **Deploy NGINX Ingress**: Configure ingress controller for Kind
3. **Set up Cert-Manager**: Local CA + Let's Encrypt ready
4. **Configure Secrets**: SOPS + External Secrets setup
5. **Monitoring Stack**: Prometheus/Grafana deployment

## Architecture Justifications

### Kind over k3s/minikube
- Better Docker Desktop integration
- Multi-node support for realistic testing
- Port mapping for easy ingress access
- Minimal macOS overhead

### ArgoCD over Flux
- Superior UI for debugging and visualization
- More mature ecosystem and documentation
- Better app-of-apps pattern support
- Easier troubleshooting workflow

### Keycloak over alternatives
- Full OIDC/SAML standards compliance
- Enterprise-grade user management
- Better integration with modern apps
- Realm-based multi-tenancy

### NGINX over Traefik
- More stable and mature
- Better performance characteristics
- Richer feature set for ingress
- Extensive configuration documentation

## Resource Allocation

- **Cluster**: 3 nodes (simplified from original 6-node plan)
- **Memory**: ~6GB allocated to Kind containers
- **CPU**: ~4 cores allocated
- **Storage**: Docker volumes on local SSD
- **Headroom**: Plenty left on Mac Studio (24 cores, 128GB RAM)

## Security Model

- **Authentication**: Keycloak OIDC for all services
- **Secrets**: SOPS-encrypted, stored in Git
- **Certificates**: Let's Encrypt with DNS-01 challenges
- **Access**: Tailscale VPN for remote connectivity
- **Network**: All services behind authentication

This plan provides the complete roadmap to continue building the homelab from its current foundation state.
