# GitOps Platform - Quick Reference Guide

Quick commands and workflows for daily operations.

## Daily Operations

### Check Platform Status

```bash
# All ArgoCD applications
kubectl get application -n argocd

# Infrastructure health
kubectl get pods -n vault -n traefik -n linkerd -n reloader

# Application health
kubectl get pods -n production -n staging -n development

# ArgoCD CLI status
argocd app list
```

### Deploy a New Application

```bash
# 1. Create Helm chart in charts/
# 2. Create environment values in charts/<app>/ci/

# 3. Create ArgoCD Application manifests
cat > applications/production/<app>.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_ORG/gitops-platform.git
    path: charts/<app>
    helm:
      valueFiles:
        - ci/production-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 4. Commit and push
git add .
git commit -m "feat: add new application"
git push

# ArgoCD will automatically deploy!
```

### Update Application Image

**Option 1: Via CI/CD (Recommended)**

```bash
# Just push code - CI will build, package, and update Git
git commit -m "feat: new feature"
git push
```

**Option 2: Manual Update**

```bash
# Update image tag in values file
vim charts/my-microservice/ci/production-values.yaml
# Change: tag: "v1.2.3"

git commit -m "chore: update to v1.2.3"
git push

# ArgoCD syncs automatically
```

### Manage Secrets

```bash
# Create secret in Vault
vault kv put secret/production/myapp/api \
  key="new-api-key" \
  secret="new-secret"

# ExternalSecret will sync automatically
# Reloader will restart pods within refreshInterval

# Force immediate sync
kubectl delete externalsecret <name> -n production
kubectl apply -f applications/production/
```

### Scale Application

```bash
# Update replicas in Git
vim charts/my-microservice/ci/production-values.yaml
# Change: replicaCount: 10

git commit -m "scale: increase replicas to 10"
git push

# Or use HPA (recommended)
# HPA is configured in values.yaml:
# autoscaling:
#   enabled: true
#   minReplicas: 3
#   maxReplicas: 10
```

### Rollback Deployment

```bash
# Option 1: Via Git
git revert <commit-hash>
git push

# Option 2: Via ArgoCD
argocd app rollback <app-name> <revision>

# Option 3: Via Kubernetes (temporary)
kubectl rollout undo deployment/<app> -n production
# Note: ArgoCD will revert this back!
```

## Troubleshooting Commands

### Application Not Syncing

```bash
# Check app status
argocd app get <app-name>

# View detailed sync status
kubectl describe application <app-name> -n argocd

# Force refresh
argocd app refresh <app-name> --hard

# Manual sync
argocd app sync <app-name> --prune
```

### Pod CrashLoopBackOff

```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check previous logs
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check secrets are mounted
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 volumes
```

### Vault Connection Issues

```bash
# Test Vault connectivity
kubectl run vault-test --rm -it --image=hashicorp/vault:1.15.4 -- sh
vault status -address=http://vault.vault.svc.cluster.local:8200

# Check ExternalSecret status
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

# Check Vault auth
vault token lookup
vault auth list
```

### Config Not Reloading

```bash
# Check Reloader is running
kubectl get pods -n reloader

# Verify annotation on deployment
kubectl get deployment <app> -n <namespace> -o yaml | grep reloader

# Should have:
# reloader.stakater.com/auto: "true"

# Check Reloader logs
kubectl logs -l app=reloader -n reloader
```

### Ingress Not Working

```bash
# Check IngressRoute
kubectl get ingressroute -n <namespace>
kubectl describe ingressroute <name> -n <namespace>

# Check Traefik
kubectl logs -l app.kubernetes.io/name=traefik -n traefik

# Test from inside cluster
kubectl run curl --rm -it --image=curlimages/curl -- sh
curl http://<service>.<namespace>.svc.cluster.local
```

### Service Mesh Issues

```bash
# Check Linkerd status
linkerd check

# Check proxy injection
kubectl get pod <pod> -n <namespace> -o yaml | grep linkerd

# View proxy logs
kubectl logs <pod> -c linkerd-proxy -n <namespace>

# Check mTLS status
linkerd viz stat deployment/<app> -n <namespace>
linkerd viz tap deployment/<app> -n <namespace>
```

## Maintenance Operations

### Backup

```bash
# Backup Vault
vault operator raft snapshot save vault-backup-$(date +%Y%m%d).snap

# Backup ArgoCD applications
kubectl get application -n argocd -o yaml > argocd-apps-backup-$(date +%Y%m%d).yaml

# Backup all manifests
kubectl get all,ingress,ingressroute,externalsecret -A -o yaml > cluster-backup-$(date +%Y%m%d).yaml
```

### Restore

```bash
# Restore Vault
vault operator raft snapshot restore vault-backup.snap

# Restore ArgoCD applications
kubectl apply -f argocd-apps-backup.yaml
```

### Update Infrastructure Component

```bash
# 1. Update Helm chart version in infrastructure/<component>/kustomization.yaml
vim infrastructure/traefik/kustomization.yaml
# Change version: 26.0.0 -> 27.0.0

# 2. Test locally (optional)
kustomize build infrastructure/traefik

# 3. Commit and push
git commit -m "chore: update traefik to v27.0.0"
git push

# 4. ArgoCD will sync automatically
# Monitor the update:
watch kubectl get pods -n traefik
```

### Rotate Credentials

```bash
# 1. Update in Vault
vault kv put secret/production/myapp/db password="new-password"

# 2. ExternalSecret syncs (wait for refreshInterval or delete/recreate)
kubectl delete externalsecret db-creds -n production

# 3. Reloader triggers rolling update
# Pods will restart with new secret
```

### Certificate Renewal

```bash
# Linkerd certificates (every ~8760h = 1 year)
cd infrastructure/linkerd
./generate-certs.sh

# Update secrets
kubectl create secret tls linkerd-identity-issuer \
  --cert=certs/issuer.crt \
  --key=certs/issuer.key \
  --namespace=linkerd \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Linkerd control plane
kubectl rollout restart deployment -n linkerd
```

## Monitoring & Debugging

### Check Resource Usage

```bash
# Top nodes
kubectl top nodes

# Top pods
kubectl top pods -n production

# Specific pod resources
kubectl describe pod <pod> -n <namespace> | grep -A 5 Resources
```

### View Logs

```bash
# Real-time logs
kubectl logs -f deployment/<app> -n <namespace>

# Logs from all pods
kubectl logs -l app=<app> -n <namespace> --all-containers=true

# Logs with timestamps
kubectl logs <pod> -n <namespace> --timestamps
```

### Debug Networking

```bash
# DNS resolution
kubectl run dnsutils --rm -it --image=gcr.io/kubernetes-e2e-test-images/dnsutils:1.3 -- nslookup <service>.<namespace>.svc.cluster.local

# Network connectivity
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- bash
curl http://<service>.<namespace>.svc.cluster.local:8080
```

### Performance Testing

```bash
# Install k6 in cluster
kubectl run k6 --rm -it --image=grafana/k6 -- run - <<EOF
import http from 'k6/http';
export default function () {
  http.get('http://my-app.production.svc.cluster.local');
}
EOF
```

## Common Workflows

### Adding a New Environment

```bash
# 1. Create namespace with Linkerd injection
kubectl create namespace <env>
kubectl annotate namespace <env> linkerd.io/inject=enabled

# 2. Create SecretStore
cat > infrastructure/external-secrets/vault-secret-store.yaml <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: <env>
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "<env>-apps"
EOF

# 3. Create Vault policy
vault policy write <env>-apps-policy - <<EOF
path "secret/data/<env>/*" {
  capabilities = ["read", "list"]
}
EOF

# 4. Create Vault role
vault write auth/kubernetes/role/<env>-apps \
  bound_service_account_names=default \
  bound_service_account_namespaces=<env> \
  policies=<env>-apps-policy \
  ttl=24h

# 5. Create App of Apps
cp applications/app-of-apps-production.yaml applications/app-of-apps-<env>.yaml
# Update namespace and path

# 6. Commit and push
git add .
git commit -m "feat: add <env> environment"
git push
```

### CI/CD Pipeline Debugging

```bash
# View GitHub Actions logs
gh run list
gh run view <run-id>

# Test CI locally with act
act -j build-and-push

# Manually trigger workflow
gh workflow run ci-build-deploy.yaml
```

## Quick Links

- **ArgoCD UI:** <https://argocd.example.com>
- **Traefik Dashboard:** <https://traefik.example.com>
- **Linkerd Dashboard:** <https://linkerd.example.com>
- **Vault UI:** <https://vault.example.com>

## Keyboard Shortcuts (ArgoCD UI)

- `Ctrl/Cmd + K` - Search
- `F` - Full screen
- `R` - Refresh
- `S` - Sync
- `D` - Diff

## Environment Variables

```bash
# ArgoCD
export ARGOCD_SERVER=argocd.example.com
export ARGOCD_AUTH_TOKEN=$(argocd account generate-token)

# Vault
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=<your-token>

# AWS
export AWS_REGION=us-east-1
export AWS_PROFILE=default
```

## Useful Aliases

Add to your `.bashrc` or `.zshrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kdp='kubectl describe pod'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'

alias argolist='argocd app list'
alias argosync='argocd app sync'
alias argoget='argocd app get'

alias vaultlogin='kubectl port-forward -n vault svc/vault 8200:8200 & export VAULT_ADDR=http://localhost:8200'
```

---

**Pro Tip:** Keep this guide bookmarked for quick access during incidents!
