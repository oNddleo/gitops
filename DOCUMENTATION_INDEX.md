# GitOps Platform Documentation Index

Complete guide to the VSF-Miniapp multi-service GitOps platform on AWS EKS.

---

## Quick Start

**New to this platform?** Start here:

1. 📖 **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** - Quick reference and overview
2. 🏗️ **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** - Detailed architecture explanations
3. 📐 **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** - Visual architecture diagrams
4. 🚀 **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** - Step-by-step implementation
5. 📝 **[CLAUDE.md](CLAUDE.md)** - Project instructions and command reference

---

## Documentation Structure

### Overview & Reference

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** | Quick reference, decision matrix, troubleshooting | Daily operations, quick lookups |
| **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** | Visual diagrams of system architecture | Understanding system flows |
| **[README.md](README.md)** | Complete platform documentation | Understanding overall platform |

### Implementation & Operations

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** | In-depth architecture explanations | Designing new services, understanding patterns |
| **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** | Step-by-step migration guide | Implementing multi-service architecture |
| **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** | Pre-deployment validation | Before deploying to production |
| **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** | Command reference | Daily kubectl/argocd operations |

### Project Guidelines

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **[CLAUDE.md](CLAUDE.md)** | Project instructions for Claude Code | AI-assisted development |
| **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** | High-level overview and file inventory | Understanding project structure |

---

## Documentation by Use Case

### "I want to add a new service to the platform"

1. Read: **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** § "Complete Example: Adding a New Service"
2. Reference: **[examples/multi-service/](examples/multi-service/)** for templates
3. Follow: **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** § "Step-by-Step Implementation"
4. Use checklist: **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** § "Service Deployment Checklist"

### "I want to understand how Linkerd mTLS works"

1. Read: **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** § "Linkerd mTLS Integration"
2. View diagram: **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** § "Service-to-Service Communication with Linkerd mTLS"
3. Quick reference: **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** § "Linkerd mTLS Implementation"

### "I want to set up AWS Secrets Manager for a service"

1. Read: **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** § "AWS Secrets Manager Integration"
2. View flow: **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** § "AWS Secrets Manager Integration Flow"
3. Follow: **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** § "AWS Secrets Manager Setup"
4. Example: **[examples/multi-service/service-a-production-values.yaml](examples/multi-service/service-a-production-values.yaml)**

### "I want to support multiple languages (Java, Node.js, Python)"

1. Read: **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** § "Multi-Language Support"
2. Compare examples:
   - **[examples/multi-service/service-a-production-values.yaml](examples/multi-service/service-a-production-values.yaml)** (Java)
   - **[examples/multi-service/service-b-production-values.yaml](examples/multi-service/service-b-production-values.yaml)** (Node.js)
3. Reference: **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** § "Multi-Language Support Strategy"

### "I'm troubleshooting a deployment issue"

1. Check: **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** § "Troubleshooting Quick Reference"
2. Detailed steps: **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** § "Troubleshooting"
3. Commands: **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** (if exists)
4. Architecture reference: **[CLAUDE.md](CLAUDE.md)** § "Troubleshooting"

### "I want to understand the App of Apps pattern"

1. Read: **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** § "App of Apps Pattern"
2. View hierarchy: **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** § "App of Apps Hierarchy"
3. Quick ref: **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** § "Component Integration Matrix"

---

## Example Files

Complete working examples for reference:

### Helm Chart Values

| File | Description |
|------|-------------|
| **[examples/multi-service/service-a-production-values.yaml](examples/multi-service/service-a-production-values.yaml)** | Java Spring Boot service configuration |
| **[examples/multi-service/service-b-production-values.yaml](examples/multi-service/service-b-production-values.yaml)** | Node.js Express service configuration |

### ArgoCD Applications

| File | Description |
|------|-------------|
| **[examples/multi-service/vsf-miniapp-service-a-production.yaml](examples/multi-service/vsf-miniapp-service-a-production.yaml)** | ArgoCD Application manifest for Service A |

### Infrastructure

| Directory | Description |
|-----------|-------------|
| **[infrastructure/linkerd/](infrastructure/linkerd/)** | Linkerd mTLS configuration |
| **[infrastructure/secrets-store-csi/](infrastructure/secrets-store-csi/)** | AWS Secrets Manager CSI driver setup |
| **[infrastructure/traefik/](infrastructure/traefik/)** | Traefik ingress controller |

---

## Key Concepts Quick Reference

### Shared Base Chart Strategy

**What:** Single Helm chart (`charts/vsf-miniapp/`) used by all services

**Why:** Consistency, maintainability, DRY principle

**How:** Service-specific values override common defaults

**Example:**
```bash
# Service A uses shared chart with Java-specific values
helm template service-a charts/vsf-miniapp \
  -f charts/vsf-miniapp/ci/service-a-production.yaml

# Service B uses same chart with Node.js-specific values
helm template service-b charts/vsf-miniapp \
  -f charts/vsf-miniapp/ci/service-b-production.yaml
```

**Read more:** [ARCHITECTURE_GUIDE.md § Multi-Service Strategy](ARCHITECTURE_GUIDE.md#1-multi-service-strategy)

---

### Linkerd mTLS

**What:** Automatic mutual TLS for all service-to-service communication

**Why:** Zero-trust security without code changes

**How:** Sidecar proxy injection via annotation

**Example:**
```yaml
podAnnotations:
  linkerd.io/inject: enabled  # That's it!
```

**Read more:** [ARCHITECTURE_GUIDE.md § Linkerd Integration](ARCHITECTURE_GUIDE.md#3-linkerd-mtls-integration)

---

### AWS Secrets Manager Integration

**What:** Mount AWS secrets as files and Kubernetes Secrets

**Why:** Centralized secret management, automatic rotation

**How:** CSI driver + IRSA + SecretProviderClass

**Components:**
1. AWS Secret (in AWS Secrets Manager)
2. IAM Role with IRSA
3. ServiceAccount with role annotation
4. SecretProviderClass (defines what to fetch)
5. CSI volume mount
6. Synced Kubernetes Secret

**Read more:** [ARCHITECTURE_GUIDE.md § AWS Secrets Manager Integration](ARCHITECTURE_GUIDE.md#4-aws-secrets-manager-integration)

---

### App of Apps Pattern

**What:** Hierarchical application management

**Why:** Deploy entire platform with one application, manage environments separately

**How:** Root app → Infrastructure apps + Environment apps → Individual service apps

**Structure:**
```
root-app.yaml
  ├─▶ infrastructure/
  │   ├─▶ linkerd
  │   ├─▶ traefik
  │   └─▶ secrets-store-csi
  └─▶ app-of-apps-production.yaml
      ├─▶ vsf-miniapp-service-a
      └─▶ vsf-miniapp-service-b
```

**Read more:** [ARCHITECTURE_GUIDE.md § App of Apps Pattern](ARCHITECTURE_GUIDE.md#5-app-of-apps-pattern)

---

## Common Commands

### Validation

```bash
# Lint Helm chart
helm lint charts/vsf-miniapp -f charts/vsf-miniapp/ci/service-a-production.yaml

# Template and validate
helm template test charts/vsf-miniapp \
  -f charts/vsf-miniapp/ci/service-a-production.yaml \
  | kubectl apply --dry-run=client -f -
```

### Deployment

```bash
# Sync ArgoCD application
argocd app sync vsf-miniapp-service-a-production

# Wait for deployment to be healthy
argocd app wait vsf-miniapp-service-a-production --health --timeout 300
```

### Verification

```bash
# Check pods
kubectl get pods -n production -l service=service-a

# Check Linkerd mTLS
linkerd viz stat deployment/service-a -n production

# Check secrets
kubectl get secret service-a-secrets -n production
kubectl exec -n production <pod> -- ls -la /mnt/secrets
```

**More commands:** [CLAUDE.md § Common Commands](CLAUDE.md#common-commands)

---

## Architecture at a Glance

```
Developer → Git → CI (Build) → Git (Updated) → ArgoCD → Kubernetes
                                                              ↓
                                                    Infrastructure Layer
                                                    ├─ Linkerd (mTLS)
                                                    ├─ Traefik (Ingress)
                                                    ├─ CSI Driver (Secrets)
                                                    └─ Reloader (Auto-restart)
                                                              ↓
                                                    Application Layer
                                                    ├─ Service A (Java)
                                                    ├─ Service B (Node.js)
                                                    └─ Service C (Python)
                                                              ↓
                                                    External Integrations
                                                    ├─ AWS Secrets Manager
                                                    ├─ AWS ECR
                                                    └─ Databases
```

**Full diagrams:** [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)

---

## Getting Help

### For Quick Questions

- **Commands:** See [CLAUDE.md § Common Commands](CLAUDE.md#common-commands)
- **Troubleshooting:** See [MULTI_SERVICE_SUMMARY.md § Troubleshooting Quick Reference](MULTI_SERVICE_SUMMARY.md#troubleshooting-quick-reference)

### For Understanding Concepts

- **Architecture:** See [ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)
- **Diagrams:** See [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)

### For Implementation

- **Step-by-step:** See [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)
- **Examples:** See [examples/multi-service/](examples/multi-service/)
- **Checklist:** See [MULTI_SERVICE_SUMMARY.md § Service Deployment Checklist](MULTI_SERVICE_SUMMARY.md#service-deployment-checklist)

---

## Document Change Log

| Date | Document | Changes |
|------|----------|---------|
| 2025-12-04 | All | Initial creation of multi-service architecture documentation |

---

## Contributing

When adding new documentation:

1. Follow the existing structure and format
2. Add entry to this index
3. Cross-reference related documents
4. Include practical examples
5. Update the "Common Commands" section if adding new operations

---

## License

This documentation is part of the VSF-Miniapp GitOps platform.

---

**Need help?** Start with [MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md) for a quick overview, then dive into specific guides based on your needs.
