# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-ready GitOps Kubernetes platform on AWS EKS implementing a fully automated CI/CD workflow with:
- **GitOps operator**: ArgoCD for continuous deployment
- **Secrets management**: HashiCorp Vault with External Secrets Operator
- **Service mesh**: Linkerd for mTLS between services
- **Ingress controller**: Traefik v3 with IngressRoute CRDs
- **Config reloading**: Reloader for automatic pod updates

## Core Architecture Principles

### GitOps Flow
1. **Git is the single source of truth** - All cluster state is declared in Git
2. **CI builds and packages** - GitHub Actions builds Docker images and Helm charts, pushes to ECR
3. **CD deploys from Git** - ArgoCD continuously syncs cluster state from Git repository
4. **Secrets from Vault** - External Secrets Operator syncs secrets from Vault to Kubernetes
5. **Auto-reload on changes** - Reloader watches ConfigMaps/Secrets and triggers rolling updates

### App of Apps Pattern
The platform uses hierarchical application management:
- `bootstrap/root-app.yaml` - Bootstraps the entire platform
- `applications/infrastructure-apps.yaml` - Manages all infrastructure components
- `applications/app-of-apps-{env}.yaml` - Manages applications per environment (dev/staging/production)

## Directory Structure

```
gitops/
├── bootstrap/               # ArgoCD bootstrap scripts and root app
│   ├── install.sh          # Bootstrap script to install ArgoCD
│   ├── argocd-namespace.yaml
│   └── root-app.yaml       # Root App of Apps
├── infrastructure/         # Platform components (Kustomize + Helm)
│   ├── vault/              # HashiCorp Vault (HA mode, DynamoDB backend, KMS auto-unseal)
│   ├── traefik/            # Traefik v3 ingress controller
│   ├── linkerd/            # Service mesh with mTLS
│   ├── reloader/           # Automatic pod updates on config changes
│   ├── external-secrets/   # Vault-to-K8s secret synchronization
│   └── argocd/             # Self-managed ArgoCD configuration
├── applications/           # Application deployment manifests
│   ├── infrastructure-apps.yaml  # Infrastructure App of Apps
│   ├── app-of-apps-{env}.yaml   # Per-environment App of Apps
│   └── {env}/              # Environment-specific application manifests
├── charts/                 # Helm charts for microservices
│   └── my-microservice/
│       ├── templates/      # Kubernetes manifests (Deployment, Service, etc.)
│       ├── values.yaml     # Default values
│       └── ci/             # Environment-specific value overrides
└── .github/workflows/      # CI/CD pipelines
```

## Common Commands

### Validation and Linting

```bash
# Lint YAML files
yamllint .

# Lint Helm charts
helm lint charts/my-microservice
helm lint charts/my-microservice -f charts/my-microservice/ci/production-values.yaml

# Template and validate Helm charts
helm template test-release charts/my-microservice --namespace default

# Validate with kubeval
helm template test-release charts/my-microservice | kubeval --ignore-missing-schemas

# Validate Kustomize overlays
kustomize build infrastructure/vault
```

### Local Development

```bash
# Connect to EKS cluster
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1

# Bootstrap the platform (initial setup only)
./bootstrap/install.sh

# Check ArgoCD applications status
kubectl get application -n argocd
argocd app list

# Check infrastructure health
kubectl get pods -n vault -n traefik -n linkerd -n reloader -n external-secrets-system

# Port forward to services for local access
kubectl port-forward -n argocd svc/argocd-server 8080:443
kubectl port-forward -n vault svc/vault 8200:8200
```

### Deploying Changes

**IMPORTANT**: Never use `kubectl apply` directly. Always commit to Git and let ArgoCD sync.

```bash
# Update application configuration
vim charts/my-microservice/ci/production-values.yaml
git add charts/my-microservice/ci/production-values.yaml
git commit -m "update: increase replicas to 5"
git push

# ArgoCD will automatically detect and sync the change
# Monitor sync progress:
argocd app get my-microservice-production
argocd app wait my-microservice-production --health --timeout 300

# Force sync if needed
argocd app sync my-microservice-production --prune
```

### Secrets Management

```bash
# Port forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR='http://localhost:8200'

# Login to Vault
vault login <token>

# Create/update secrets
vault kv put secret/production/myapp/database \
  url="postgresql://prod-db:5432/myapp" \
  username="app_user" \
  password="secret-password"

# External Secrets Operator will sync within refreshInterval (default: 1h)
# Check ExternalSecret status
kubectl get externalsecret -n production
kubectl describe externalsecret my-microservice-secrets -n production

# Reloader will automatically trigger rolling update when secret changes
```

### Troubleshooting

```bash
# ArgoCD app not syncing
argocd app get <app-name>
kubectl describe application <app-name> -n argocd
argocd app refresh <app-name> --hard

# Pod issues
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check Linkerd proxy injection
kubectl get pod <pod> -n <namespace> -o yaml | grep linkerd-proxy
linkerd check
linkerd viz stat deployment -n production

# Vault connectivity issues
kubectl run vault-test --rm -it --image=hashicorp/vault:1.15.4 -- sh
# Inside container: vault status -address=http://vault.vault.svc.cluster.local:8200

# Check Reloader
kubectl get pods -n reloader
kubectl logs -l app=reloader -n reloader
```

## Important Configuration Patterns

### Helm Chart Template Structure

All application Helm charts follow this pattern:
- **Deployment** with Linkerd injection (`linkerd.io/inject: enabled`) and Reloader annotation (`reloader.stakater.com/auto: "true"`)
- **Service** exposing application ports
- **ServiceAccount** for IRSA integration
- **ConfigMap** for non-sensitive configuration
- **ExternalSecret** for Vault-sourced secrets (not native Secrets in Git)
- **IngressRoute** (Traefik CRD) for external access
- **HorizontalPodAutoscaler** for auto-scaling
- **ServiceMonitor** for Prometheus metrics

### Infrastructure Component Updates

Infrastructure components are managed via Kustomize with Helm charts:

```yaml
# infrastructure/{component}/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: {component}
helmCharts:
  - name: {chart-name}
    repo: {helm-repo-url}
    version: {version}
    releaseName: {release-name}
    valuesInline:
      # Helm values here
```

To update a component version:
1. Edit `infrastructure/{component}/kustomization.yaml`
2. Update the `version` field
3. Commit and push - ArgoCD will sync automatically

### Adding a New Application

1. Create Helm chart in `charts/{app-name}/`
2. Create environment-specific values in `charts/{app-name}/ci/{env}-values.yaml`
3. Create ArgoCD Application manifests in `applications/{env}/{app-name}.yaml`
4. Commit and push - ArgoCD will deploy automatically

### CI/CD Pipeline Behavior

The CI pipeline (`.github/workflows/ci-build-deploy.yaml`) triggers on pushes to `main` or `develop`:
1. Lints Helm charts with all environment values
2. Validates manifests with kubeval
3. Builds Docker image and pushes to ECR
4. Packages Helm chart and pushes to ECR (OCI format)
5. Updates `charts/{app}/ci/production-values.yaml` with new image tag
6. Commits changes back to Git
7. Notifies ArgoCD to sync

Expected deployment time: < 5 minutes from commit to production

## Critical Files to Update Before Deployment

When setting up a new instance of this platform, update:
1. **Repository URLs**: Replace `YOUR_ORG/gitops-platform` in all `*.yaml` files
2. **ECR Registry**: Replace `YOUR_ECR_REGISTRY` in `charts/*/values.yaml`
3. **Domain Names**: Replace `example.com` in all ingress configurations
4. **AWS Account**: Replace `ACCOUNT_ID` in Vault IRSA annotations
5. **AWS Region**: Update region in Vault kustomization and workflows
6. **Vault KMS Key**: Replace `VAULT_KMS_KEY_ID` in `infrastructure/vault/kustomization.yaml`

## Testing Strategy

```bash
# Test Helm chart rendering
helm template test charts/my-microservice -f charts/my-microservice/ci/production-values.yaml

# Test with different environments
for env in dev staging production; do
  helm template test charts/my-microservice -f charts/my-microservice/ci/${env}-values.yaml
done

# Validate generated manifests
helm template test charts/my-microservice | kubectl apply --dry-run=client -f -

# Check ArgoCD app health
argocd app list
argocd app get my-microservice-production

# Verify all infrastructure apps are healthy
kubectl get application -n argocd | grep -E "Synced|Healthy"
```

## Security Considerations

- **Never commit secrets to Git** - Use Vault with External Secrets Operator
- **All service-to-service traffic uses mTLS** - Enabled via Linkerd proxy injection
- **Read-only root filesystems** - Enforced in pod security contexts
- **Non-root containers** - All containers run as non-root users
- **RBAC enabled** - Service accounts with least-privilege policies
- **Vault auto-unseal** - Uses AWS KMS for automatic unsealing
- **TLS everywhere** - Traefik handles TLS termination with cert-manager integration

## Component Versions

- Kubernetes: 1.28+
- ArgoCD: 6.7.3
- Vault: 1.15.4 (Helm chart 0.28.0)
- Traefik: v26.0.0
- Linkerd: Control plane 1.16.11, Viz 30.12.11
- Reloader: 1.0.79
- External Secrets: 0.9.13
- Helm: 3.14.0

## Additional Documentation

- `README.md` - Complete platform documentation with architecture diagrams
- `DEPLOYMENT_CHECKLIST.md` - Step-by-step deployment guide
- `QUICK_REFERENCE.md` - Command reference for daily operations
- `IMPLEMENTATION_SUMMARY.md` - High-level overview and file inventory
