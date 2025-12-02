# GitOps Kubernetes Platform on AWS EKS

A production-ready, GitOps-based Kubernetes platform running on Amazon EKS with complete CI/CD automation, secrets management, service mesh, and observability.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Guide](#deployment-guide)
- [CI/CD Pipeline](#cicd-pipeline)
- [Secrets Management](#secrets-management)
- [Networking & Ingress](#networking--ingress)
- [Service Mesh](#service-mesh)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Architecture Overview

This platform implements a complete GitOps workflow where:

1. **Git is the single source of truth** for all cluster configuration and application state
2. **CI builds and packages** applications into OCI artifacts (Helm charts + Docker images)
3. **CD (ArgoCD) deploys** from Git declarations, pulling artifacts from registries
4. **Vault provides dynamic secrets** injected at deploy time via External Secrets Operator
5. **Service Mesh (Linkerd)** enables mTLS for all service-to-service communication
6. **Reloader watches** ConfigMaps/Secrets and triggers rolling updates automatically

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   Git Repository  │
                    │  (Source of Truth)│
                    └──────────────────┘
                              │
                ┌─────────────┴─────────────┐
                ▼                           ▼
        ┌───────────────┐          ┌──────────────┐
        │  CI Pipeline  │          │   ArgoCD     │
        │ (GitHub       │          │ (GitOps      │
        │  Actions)     │          │  Operator)   │
        └───────────────┘          └──────────────┘
                │                           │
                ▼                           ▼
        ┌───────────────┐          ┌──────────────┐
        │  ECR/OCI      │────────▶ │  EKS Cluster │
        │  Registry     │          │              │
        └───────────────┘          └──────────────┘
                                            │
                    ┌───────────────────────┼───────────────────────┐
                    ▼                       ▼                       ▼
            ┌──────────────┐      ┌──────────────┐       ┌──────────────┐
            │   Traefik    │      │   Linkerd    │       │    Vault     │
            │   Ingress    │      │Service Mesh  │       │   Secrets    │
            └──────────────┘      └──────────────┘       └──────────────┘
```

---

## Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Orchestration** | Amazon EKS | 1.28+ | Managed Kubernetes control plane |
| **GitOps** | ArgoCD | 6.7.3 | Continuous deployment operator |
| **Package Manager** | Helm | 3.14+ | Application packaging |
| **Configuration** | Kustomize | 5.0+ | Environment-specific overlays |
| **Secrets** | HashiCorp Vault | 1.15+ | Dynamic secrets management |
| **Secret Sync** | External Secrets | 0.9.13 | Vault-to-K8s secret synchronization |
| **Config Reload** | Reloader | 1.0.79 | Automatic pod updates on config changes |
| **Service Mesh** | Linkerd | 2.14+ | mTLS, traffic management |
| **Ingress** | Traefik v3 | 26.0+ | API Gateway and ingress controller |
| **CI** | GitHub Actions | - | Build, test, package automation |

---

## Prerequisites

### Required Tools

```bash
# Install required CLI tools
brew install kubectl helm aws-cli argocd terraform step jq yq
```

### AWS Resources

Before deploying, you need:

1. **EKS Cluster** (1.28+)
2. **ECR Repository** for Docker images and Helm charts
3. **DynamoDB Table** for Vault storage
4. **S3 Bucket** for Vault snapshots
5. **KMS Key** for Vault auto-unseal
6. **IAM Role** for Vault service account (IRSA)

**Deploy AWS resources using Terraform:**

```bash
cd infrastructure/vault
terraform init
terraform plan
terraform apply
```

---

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/YOUR_ORG/gitops-platform.git
cd gitops-platform

# Update repository URLs
find . -type f -name "*.yaml" -exec sed -i '' \
  's|YOUR_ORG/gitops-platform|your-org/gitops-platform|g' {} +

# Update ECR registry
find . -type f -name "*.yaml" -exec sed -i '' \
  's|YOUR_ECR_REGISTRY|123456789012.dkr.ecr.us-east-1.amazonaws.com|g' {} +

# Update domain names
find . -type f -name "*.yaml" -exec sed -i '' \
  's|example.com|yourdomain.com|g' {} +
```

### 2. Connect to EKS Cluster

```bash
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1
kubectl cluster-info
```

### 3. Bootstrap the Platform

```bash
cd bootstrap
./install.sh
```

This script will:

- Install ArgoCD via Helm
- Deploy the root App of Apps
- Configure GitOps automation

**Expected output:**

```
ArgoCD URL: https://a123456789.us-east-1.elb.amazonaws.com
Username: admin
Password: <random-password>
```

### 4. Access ArgoCD UI

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward if not using LoadBalancer
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser
open https://localhost:8080
```

### 5. Verify Deployment

```bash
# Check all ArgoCD applications
kubectl get application -n argocd

# Check infrastructure pods
kubectl get pods -n vault
kubectl get pods -n traefik
kubectl get pods -n linkerd
kubectl get pods -n reloader

# Verify all apps are healthy
argocd app list
```

---

## Deployment Guide

### Phase 1: Infrastructure Components

The infrastructure is deployed automatically via the App of Apps pattern:

```bash
# Verify infrastructure apps are synced
kubectl get application -n argocd | grep infrastructure

# Expected output:
# vault                  Synced  Healthy
# traefik                Synced  Healthy
# linkerd                Synced  Healthy
# reloader               Synced  Healthy
# external-secrets       Synced  Healthy
# argocd-self-managed    Synced  Healthy
```

### Phase 2: Configure Vault

#### Generate Linkerd Certificates

```bash
cd infrastructure/linkerd
./generate-certs.sh

# Apply certificates to cluster
kubectl create namespace linkerd
kubectl create secret tls linkerd-trust-anchor \
  --cert=certs/ca.crt \
  --key=certs/ca.key \
  --namespace=linkerd

kubectl create secret tls linkerd-identity-issuer \
  --cert=certs/issuer.crt \
  --key=certs/issuer.key \
  --namespace=linkerd
```

#### Initialize Vault

```bash
# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s

# Port forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &

export VAULT_ADDR='http://localhost:8200'

# Initialize Vault (save the output securely!)
vault operator init -key-shares=5 -key-threshold=3

# Unseal Vault (use 3 of the 5 unseal keys)
vault operator unseal <KEY1>
vault operator unseal <KEY2>
vault operator unseal <KEY3>

# Login with root token
vault login <ROOT_TOKEN>

# Setup Kubernetes auth and policies
kubectl exec -n argocd deployment/argocd-application-controller -- \
  /bin/bash /tmp/setup-vault.sh
```

#### Create Example Secrets in Vault

```bash
# Production secrets
vault kv put secret/production/myapp/database \
  url="postgresql://prod-db.example.com:5432/myapp" \
  username="app_user" \
  password="super-secret-password"

vault kv put secret/production/myapp/api \
  key="prod-api-key-12345"

# Staging secrets
vault kv put secret/staging/myapp/database \
  url="postgresql://staging-db.example.com:5432/myapp" \
  username="app_user" \
  password="staging-password"

# Shared secrets
vault kv put secret/shared/config \
  jwt_secret="shared-jwt-secret"
```

### Phase 3: Deploy Applications

```bash
# Deploy production App of Apps
kubectl apply -f applications/app-of-apps-production.yaml

# Deploy staging App of Apps
kubectl apply -f applications/app-of-apps-staging.yaml

# Deploy dev App of Apps
kubectl apply -f applications/app-of-apps-dev.yaml

# Verify applications
argocd app list
kubectl get application -n argocd
```

---

## CI/CD Pipeline

### CI: Build and Package

The CI pipeline (`.github/workflows/ci-build-deploy.yaml`) performs:

1. **Lint** Helm charts
2. **Build** Docker image
3. **Push** to ECR
4. **Package** Helm chart
5. **Push** Helm chart to OCI registry
6. **Update** Git with new image tag
7. **Trigger** ArgoCD sync

### CD: ArgoCD Automatic Deployment

ArgoCD continuously:

1. **Watches** Git repository for changes
2. **Compares** desired state (Git) vs actual state (cluster)
3. **Syncs** differences automatically
4. **Retrieves** secrets from Vault via External Secrets Operator
5. **Triggers** Reloader for rolling updates on config changes

### Triggering a Deployment

```bash
# Push code to trigger CI
git add .
git commit -m "feat: new feature"
git push origin main

# CI pipeline will:
# 1. Build image: 123456789.dkr.ecr.us-east-1.amazonaws.com/my-microservice:v1.2.3
# 2. Package Helm chart
# 3. Update charts/my-microservice/ci/production-values.yaml with new tag
# 4. Commit and push

# ArgoCD will automatically detect the Git change and deploy
# Expected time: ~5 minutes from commit to running in production
```

---

## Secrets Management

### Using External Secrets with Vault

**1. Create Secret in Vault:**

```bash
vault kv put secret/production/myapp/db \
  host="db.example.com" \
  username="dbuser" \
  password="secretpass"
```

**2. Create ExternalSecret:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: db-credentials
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: secret/production/myapp/db
        property: host
```

**3. Use in Deployment:**

```yaml
envFrom:
  - secretRef:
      name: db-credentials
```

Reloader will automatically trigger a rolling update when the secret changes!

---

## Networking & Ingress

### Traefik IngressRoute

All ingress uses Traefik's `IngressRoute` CRD for advanced features:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.example.com`)
      kind: Rule
      services:
        - name: my-app
          port: 80
      middlewares:
        - name: rate-limit
        - name: default-headers
  tls:
    secretName: myapp-tls
```

### Accessing Dashboards

```bash
# Traefik Dashboard
# URL: https://traefik.example.com
# Credentials: admin / changeme (update in production!)

# ArgoCD
# URL: https://argocd.example.com

# Linkerd Viz
# URL: https://linkerd.example.com

# Vault UI
# URL: https://vault.example.com
```

---

## Service Mesh

### Linkerd mTLS

All services in namespaces with `linkerd.io/inject: enabled` annotation automatically get:

- **Mutual TLS** for service-to-service communication
- **Automatic retries** and timeouts
- **Traffic metrics** and observability

### Enable Linkerd for a Namespace

```bash
kubectl annotate namespace production linkerd.io/inject=enabled
```

### Check mTLS Status

```bash
linkerd viz stat deployment -n production
linkerd viz tap deployment/my-app -n production
```

---

## Monitoring & Observability

### Service Monitors

Applications expose Prometheus metrics automatically:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    path: /metrics
```

### Key Metrics Endpoints

- **Traefik:** `:9100/metrics`
- **ArgoCD:** `:8082/metrics`
- **Linkerd:** `:4191/metrics`
- **Vault:** `:8200/v1/sys/metrics`

---

## Troubleshooting

### ArgoCD App Not Syncing

```bash
# Check app status
argocd app get my-microservice-production

# Check sync errors
kubectl describe application my-microservice-production -n argocd

# Force sync
argocd app sync my-microservice-production --prune

# Refresh and hard refresh
argocd app refresh my-microservice-production
argocd app refresh my-microservice-production --hard
```

### Vault Secrets Not Syncing

```bash
# Check External Secrets status
kubectl get externalsecret -n production
kubectl describe externalsecret db-credentials -n production

# Check Vault connectivity
kubectl run vault-test --rm -it --image=hashicorp/vault:1.15.4 -- sh
vault status -address=http://vault.vault.svc.cluster.local:8200
```

### Pods Not Reloading on Config Changes

```bash
# Check Reloader is running
kubectl get pods -n reloader

# Verify annotations on deployment
kubectl get deployment my-app -o yaml | grep reloader

# Required annotation:
# reloader.stakater.com/auto: "true"
```

### Linkerd Issues

```bash
# Check Linkerd health
linkerd check

# Check proxy injection
kubectl get pod my-app-xxx -o yaml | grep linkerd

# View proxy logs
kubectl logs my-app-xxx -c linkerd-proxy -n production
```

---

## Best Practices

### 1. Never `kubectl apply` Manually

Always commit changes to Git and let ArgoCD sync:

```bash
# ❌ DON'T
kubectl apply -f deployment.yaml

# ✅ DO
git add deployment.yaml
git commit -m "update: increase replicas"
git push
```

### 2. Use Semantic Versioning

```bash
# Tag releases properly
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

### 3. Environment Promotion

```bash
# Test in dev first
git push origin develop

# After validation, promote to production
git checkout main
git merge develop
git push origin main
```

### 4. Backup Critical Data

```bash
# Backup Vault
vault operator raft snapshot save backup.snap

# Backup ArgoCD applications
kubectl get application -n argocd -o yaml > argocd-backup.yaml
```

### 5. Rotate Secrets Regularly

```bash
# Update secret in Vault
vault kv put secret/production/myapp/db password="new-password"

# External Secrets Operator will sync within refreshInterval
# Reloader will trigger rolling update automatically
```

---

## Success Criteria Validation

Verify the platform meets all success criteria:

### ✅ Automated Deployment (< 5 minutes)

```bash
# Start timer
time git push origin main

# Watch ArgoCD
argocd app wait my-microservice-production --timeout 300

# Expected: < 5 minutes from commit to running
```

### ✅ Vault Secret Changes Trigger Rollouts

```bash
# Update secret in Vault
vault kv put secret/production/myapp/db password="new-pass"

# Watch pods restart (should happen within refreshInterval + Reloader delay)
kubectl get pods -n production -w
```

### ✅ Traefik Dashboard Accessible

```bash
# Access dashboard
open https://traefik.example.com

# Should see:
# - All IngressRoutes
# - Active middlewares
# - Traffic statistics
```

### ✅ ArgoCD Shows All Apps Healthy

```bash
kubectl get application -n argocd

# All apps should show:
# STATUS: Synced, Healthy
```

---

## Contributing

1. Create a feature branch
2. Make changes
3. Test in dev environment
4. Submit PR
5. After approval, merge to main

---

## License

MIT License - see LICENSE file

---

## Support

- **Documentation:** [docs/](./docs/)
- **Issues:** <https://github.com/YOUR_ORG/gitops-platform/issues>
- **Slack:** #gitops-platform

---

