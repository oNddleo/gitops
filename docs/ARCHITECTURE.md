# Architecture & Design

## System Overview

The VSF-Miniapp platform is a GitOps-based microservice architecture running on AWS EKS.

### Key Components
- **GitOps Engine:** ArgoCD (Self-managed)
- **Service Mesh:** Linkerd (mTLS, Observability)
- **Ingress:** Traefik v3 (IngressRoute CRDs)
- **Secret Management:** AWS Secrets Manager + CSI Driver
- **CI/CD:** GitHub Actions -> ECR -> ArgoCD

---

## Architecture Diagram

```
┌──────────────────────┐       ┌───────────────────────┐
│  GitHub Actions CI   │       │      ArgoCD           │
│  (Build & Push)      │──────▶│   (GitOps Sync)       │
└──────────────────────┘       └───────────┬───────────┘
           │                               │
           ▼                               ▼
┌───────────────────────────────────────────────────────┐
│  AWS EKS CLUSTER                                      │
│                                                       │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐  │
│  │  Traefik    │──▶│  Linkerd    │──▶│ Application │  │
│  │  Ingress    │   │  Proxy      │   │  Container  │  │
│  └─────────────┘   └─────────────┘   └──────┬──────┘  │
│                                             │         │
└─────────────────────────────────────────────┼─────────┘
                                              │
                                              ▼
                                   ┌────────────────────┐
                                   │ AWS Secrets Manager│
                                   └────────────────────┘
```

---

## Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Orchestration** | Amazon EKS | 1.28+ | Managed Kubernetes control plane |
| **GitOps** | ArgoCD | 2.10+ | Continuous deployment operator |
| **Package Manager** | Helm | 3.14+ | Application packaging |
| **Configuration** | Kustomize | 5.0+ | Environment-specific overlays |
| **Secrets** | AWS Secrets Manager | - | Fully managed secrets service |
| **Secret Sync** | Secrets Store CSI Driver | 1.4.1 | Mount secrets as volumes |
| **Config Reload** | Reloader | 1.0.79 | Automatic pod updates on config changes |
| **Service Mesh** | Linkerd | 2.14+ | mTLS, traffic management |
| **Ingress** | Traefik v3 | 26.0+ | API Gateway and ingress controller |
| **CI** | GitHub Actions | - | Build, test, package automation |

---

## Security Architecture

### mTLS (Mutual TLS)
- **Linkerd** automatically encrypts all East-West traffic.
- No application code changes required.
- Enabled via annotation: `linkerd.io/inject: enabled`.

### Secret Management Architecture
Secrets are never stored in Git. The flow works as follows:

```
AWS Secrets Manager
       ↓
   (IRSA via OIDC)
       ↓
Secrets Store CSI Driver (DaemonSet)
       ↓
   AWS Provider
       ↓
SecretProviderClass (per app/namespace)
       ↓
Pod with CSI Volume
  ├── /mnt/secrets/db-url      ← Mounted as files
  ├── /mnt/secrets/db-pass
  └── env: DATABASE_URL        ← From synced K8s Secret
       ↓
Reloader watches Secret changes
       ↓
Triggers rolling update
```

### Networking & Ingress
All ingress uses Traefik's `IngressRoute` CRD for advanced features:
- **EntryPoints:** web (80), websecure (443)
- **Middlewares:** Rate limiting, security headers, compression
- **TLS Termination:** Managed by Traefik (can integrate with cert-manager)

---

## Multi-Service Strategy

We use a **Shared Base Chart** (`charts/vsf-miniapp`) for all services to ensure consistency.

### Directory Structure
```
charts/vsf-miniapp/          # Shared Chart
├── templates/               # K8s Manifests (Deployment, SVC, SA, etc.)
└── ci/                      # Per-Service Values
    ├── service-a-dev.yaml
    ├── service-b-prod.yaml
    └── ...
```

### Supported Languages
- **Java (Spring Boot):** Uses `openjdk-17`, port `8080`, slower startup probes.
- **Node.js (Express):** Uses `node-20`, port `3000`, fast startup.
- **Python (FastAPI):** Uses `python-3.11`, port `8000`.

---

## Implementation Summary

| Feature | Implementation |
|---------|----------------|
| **Deployment** | ArgoCD App of Apps |
| **Scaling** | HPA (CPU/Memory) |
| **Routing** | Traefik IngressRoute |
| **Observability** | Prometheus + Linkerd Viz |
| **High Availability**| Pod Anti-Affinity + Multi-AZ |