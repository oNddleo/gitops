# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-ready GitOps Kubernetes platform on AWS EKS implementing a fully automated CI/CD workflow with:
- **GitOps operator**: ArgoCD for continuous deployment
- **Secrets management**: AWS Secrets Manager integrated via Kubernetes Secrets Store CSI Driver
- **Service mesh**: Linkerd for mTLS between services
- **Ingress controller**: Traefik v3 with IngressRoute CRDs
- **Config reloading**: Reloader for automatic pod updates

## Core Architecture Principles

### GitOps Flow
1. **Git is the single source of truth** - All cluster state is declared in Git
2. **CI builds and packages** - GitHub Actions builds Docker images and Helm charts, pushes to ECR
3. **CD deploys from Git** - ArgoCD continuously syncs cluster state from Git repository
4. **Secrets from AWS Secrets Manager** - Secrets Store CSI Driver mounts secrets as volumes and syncs to Kubernetes Secrets
5. **Auto-reload on changes** - Reloader watches ConfigMaps/Secrets and triggers rolling updates

### App of Apps Pattern
The platform uses hierarchical application management:
- `bootstrap/root-app.yaml` - Root Application pointing to `applications/infrastructure/`
- `applications/infrastructure/` - Individual ArgoCD Application manifests for each infrastructure component
  - `00-project.yaml` - Infrastructure project definition
  - `argocd-self-managed.yaml` - ArgoCD self-management
  - `linkerd.yaml` - Service mesh
  - `traefik.yaml` - Ingress controller
  - `secrets-store-csi.yaml` - CSI driver
  - `reloader.yaml` - Config reloader
- `applications/app-of-apps-{env}.yaml` - Manages applications per environment (dev/staging/production)

## Directory Structure

```
gitops/
├── bootstrap/               # ArgoCD bootstrap scripts and root app
│   ├── install.sh          # Bootstrap script to install ArgoCD
│   ├── argocd-namespace.yaml
│   └── root-app.yaml       # Root App of Apps
├── infrastructure/         # Platform components (Kustomize + Helm)
│   ├── secrets-store-csi/  # AWS Secrets Manager CSI Driver integration
│   ├── traefik/            # Traefik v3 ingress controller
│   ├── linkerd/            # Service mesh with mTLS
│   ├── reloader/           # Automatic pod updates on config changes
│   └── argocd/             # Self-managed ArgoCD configuration
├── applications/           # ArgoCD Application manifests
│   ├── infrastructure/     # Infrastructure component Applications
│   │   ├── 00-project.yaml
│   │   ├── argocd-self-managed.yaml
│   │   ├── linkerd.yaml
│   │   ├── traefik.yaml
│   │   ├── secrets-store-csi.yaml
│   │   └── reloader.yaml
│   ├── app-of-apps-{env}.yaml   # Per-environment App of Apps
│   ├── dev/                # Development application manifests
│   ├── staging/            # Staging application manifests
│   └── production/         # Production application manifests
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
kustomize build infrastructure/secrets-store-csi
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
kubectl get pods -n kube-system | grep secrets-store-csi
kubectl get pods -n traefik -n linkerd -n reloader

# Port forward to services for local access
kubectl port-forward -n argocd svc/argocd-server 8080:443
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
# Create/update secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name production/myapp/database \
  --description "Database credentials for myapp production" \
  --secret-string '{"url":"postgresql://prod-db:5432/myapp","username":"app_user","password":"secret-password"}' \
  --region us-east-1

# Update existing secret
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '{"url":"postgresql://prod-db:5432/myapp","username":"app_user","password":"new-password"}' \
  --region us-east-1

# List all secrets
aws secretsmanager list-secrets --region us-east-1

# Get secret value
aws secretsmanager get-secret-value \
  --secret-id production/myapp/database \
  --region us-east-1

# Check SecretProviderClass status
kubectl get secretproviderclass -n production
kubectl describe secretproviderclass my-microservice-secrets -n production

# Check if secret is mounted in pod
kubectl exec -n production <pod-name> -- ls -la /mnt/secrets

# Check synced Kubernetes Secret (if using secretObjects in SecretProviderClass)
kubectl get secret my-microservice-secrets -n production
kubectl describe secret my-microservice-secrets -n production

# CSI Driver will automatically sync secret updates based on rotationPollInterval (default: 2 minutes)
# Reloader will automatically trigger rolling update when synced Kubernetes Secret changes
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

# CSI Driver issues
kubectl get pods -n kube-system | grep csi
kubectl logs -n kube-system -l app=secrets-store-csi-driver
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws

# Check if SecretProviderClass is working
kubectl describe secretproviderclass <name> -n <namespace>

# Check CSI driver events
kubectl get events -n <namespace> | grep ProviderVolume

# Verify pod has CSI volume mounted
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Volumes:"

# Test IRSA permissions
kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=<service-account-name> -n <namespace> -- \
  secretsmanager get-secret-value --secret-id production/myapp/database --region us-east-1

# Check Reloader
kubectl get pods -n reloader
kubectl logs -l app=reloader -n reloader
```

## Important Configuration Patterns

### Helm Chart Template Structure

All application Helm charts follow this pattern:
- **Deployment** with Linkerd injection (`linkerd.io/inject: enabled`) and Reloader annotation (`reloader.stakater.com/auto: "true"`)
  - Must include CSI volume mount for secrets
  - ServiceAccount must have IRSA annotation for AWS Secrets Manager access
- **Service** exposing application ports
- **ServiceAccount** with IRSA annotation (`eks.amazonaws.com/role-arn`)
- **ConfigMap** for non-sensitive configuration
- **SecretProviderClass** for AWS Secrets Manager integration (not native Secrets in Git)
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

**CRITICAL**: All ArgoCD Applications that reference infrastructure components using Kustomize with Helm charts **MUST** include the `--enable-helm` build option:

```yaml
# applications/infrastructure/{component}.yaml
spec:
  source:
    path: infrastructure/{component}
    kustomize:
      buildOptions: --enable-helm  # REQUIRED for Helm chart inflation
```

Without this, ArgoCD will fail with: `must specify --enable-helm`

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
4. **AWS Account**: Replace `ACCOUNT_ID` in IRSA role ARNs for ServiceAccounts
5. **AWS Region**: Update region in SecretProviderClass manifests, workflows, and Terraform
6. **IAM Role ARN**: Update `eks.amazonaws.com/role-arn` annotations in ServiceAccounts

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

- **Never commit secrets to Git** - Use AWS Secrets Manager with CSI Driver
- **All service-to-service traffic uses mTLS** - Enabled via Linkerd proxy injection
- **Read-only root filesystems** - Enforced in pod security contexts
- **Non-root containers** - All containers run as non-root users
- **RBAC enabled** - Service accounts with least-privilege IAM policies via IRSA
- **Secrets encryption at rest** - AWS Secrets Manager handles encryption with AWS KMS
- **Automatic secret rotation** - CSI Driver supports automatic secret rotation (rotationPollInterval)
- **TLS everywhere** - Traefik handles TLS termination with cert-manager integration

## Component Versions

- Kubernetes: 1.28+
- ArgoCD: 9.0.6
- Secrets Store CSI Driver: 1.4.1
- AWS Secrets Manager Provider: 0.3.7
- Traefik: v26.0.0
- Linkerd: Control plane 1.16.11, Viz 30.12.11
- Reloader: 1.0.79
- Helm: 3.14.0

## Additional Documentation

- `README.md` - Complete platform documentation with architecture diagrams
- `DEPLOYMENT_CHECKLIST.md` - Step-by-step deployment guide
- `QUICK_REFERENCE.md` - Command reference for daily operations
- `IMPLEMENTATION_SUMMARY.md` - High-level overview and file inventory
