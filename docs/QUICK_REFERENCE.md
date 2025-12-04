# GitOps Platform - Quick Reference Guide

Quick commands and workflows for daily operations.

## Daily Operations

### Check Platform Status

```bash
# All ArgoCD applications
kubectl get application -n argocd

# Infrastructure health
kubectl get pods -n kube-system | grep csi
kubectl get pods -n traefik
kubectl get pods -n linkerd
kubectl get pods -n reloader

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
# Create secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name production/myapp/api \
  --description "Production API credentials" \
  --secret-string '{"key":"new-api-key","secret":"new-secret"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=production

# Update existing secret
aws secretsmanager update-secret \
  --secret-id production/myapp/api \
  --secret-string '{"key":"updated-key","secret":"updated-secret"}' \
  --region us-east-1

# List all secrets
aws secretsmanager list-secrets --region us-east-1

# Get secret value
aws secretsmanager get-secret-value \
  --secret-id production/myapp/api \
  --region us-east-1

# Check SecretProviderClass status
kubectl get secretproviderclass -n production
kubectl describe secretproviderclass my-microservice-secrets -n production

# Check if secret is mounted in pod
kubectl exec -n production <pod-name> -- ls -la /mnt/secrets

# Check synced Kubernetes Secret
kubectl get secret my-microservice-secrets -n production
kubectl describe secret my-microservice-secrets -n production

# CSI Driver syncs automatically (default: 2-minute poll interval)
# Reloader triggers rolling update when Kubernetes Secret changes
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
kubectl exec -n <namespace> <pod-name> -- ls -la /mnt/secrets
```

### AWS Secrets Manager & CSI Driver Issues

```bash
# Check CSI Driver pods
kubectl get pods -n kube-system | grep csi
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Check AWS Provider logs
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws

# Check SecretProviderClass
kubectl get secretproviderclass -A
kubectl describe secretproviderclass <name> -n <namespace>

# Check if secret exists in AWS
aws secretsmanager describe-secret --secret-id production/myapp/database --region us-east-1
aws secretsmanager get-secret-value --secret-id production/myapp/database --region us-east-1

# Test IRSA permissions from pod
kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=<service-account-name> -n <namespace> -- \
  sts get-caller-identity

kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=<service-account-name> -n <namespace> -- \
  secretsmanager get-secret-value --secret-id production/myapp/database --region us-east-1

# Check pod events for CSI errors
kubectl describe pod <pod-name> -n <namespace> | grep -A 20 Events

# Check if CSI volume is mounted
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Volumes:"

# Check CSI driver events
kubectl get events -n <namespace> | grep ProviderVolume
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
# Backup ArgoCD applications
kubectl get application -n argocd -o yaml > argocd-apps-backup-$(date +%Y%m%d).yaml

# Backup Linkerd certificates
cp -r infrastructure/linkerd/certs linkerd-certs-backup-$(date +%Y%m%d)/

# Export AWS Secrets Manager inventory (for documentation/DR)
aws secretsmanager list-secrets --region us-east-1 > secrets-inventory-$(date +%Y%m%d).json

# Backup all manifests
kubectl get all,ingress,ingressroute,secretproviderclass -A -o yaml > cluster-backup-$(date +%Y%m%d).yaml
```

### Restore

```bash
# Restore ArgoCD applications
kubectl apply -f argocd-apps-backup.yaml

# Note: Secrets are in AWS Secrets Manager (no restore needed unless AWS account lost)
# Restore Linkerd certificates if needed
kubectl create secret tls linkerd-identity-issuer \
  --cert=linkerd-certs-backup/issuer.crt \
  --key=linkerd-certs-backup/issuer.key \
  --namespace=linkerd \
  --dry-run=client -o yaml | kubectl apply -f -
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

### Rotate Secrets

```bash
# 1. Update in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/db \
  --secret-string '{"url":"postgresql://...","password":"new-password"}' \
  --region us-east-1

# 2. CSI Driver will sync automatically (default: 2-minute poll interval)
# Wait ~2 minutes or check secret in pod:
kubectl exec -n production <pod> -- cat /mnt/secrets/database-password

# 3. Reloader will trigger rolling update when Kubernetes Secret changes
kubectl get events -n production --sort-by='.lastTimestamp' | grep Reloader
kubectl get pods -n production -w

# Or force immediate sync by deleting and recreating the pod:
kubectl delete pod -n production -l app=my-microservice
```

### Certificate Renewal

```bash
# Linkerd certificates (renew annually ~8760h)
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
kubectl run dnsutils --rm -it --image=gcr.io/kubernetes-e2e-test-images/dnsutils:1.3 -- \
  nslookup <service>.<namespace>.svc.cluster.local

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

# 2. Create secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name <env>/myapp/database \
  --secret-string '{"url":"...","password":"..."}' \
  --region us-east-1 \
  --tags Key=Environment,Value=<env>

# 3. Update Helm values for the environment
cp charts/my-microservice/ci/dev-values.yaml charts/my-microservice/ci/<env>-values.yaml
vim charts/my-microservice/ci/<env>-values.yaml
# Update: namespace, secretsManager.objects paths, etc.

# 4. Create App of Apps
cp applications/app-of-apps-dev.yaml applications/app-of-apps-<env>.yaml
vim applications/app-of-apps-<env>.yaml
# Update: namespace, targetNamespace, valueFiles

# 5. Commit and push
git add .
git commit -m "feat: add <env> environment"
git push

# 6. Deploy
kubectl apply -f applications/app-of-apps-<env>.yaml
```

### CI/CD Pipeline Debugging

```bash
# View GitHub Actions logs (requires gh CLI)
gh run list
gh run view <run-id>

# Test CI locally with act (https://github.com/nektos/act)
act -j build-and-push

# Manually trigger workflow
gh workflow run ci-build-deploy.yaml
```

## Quick Links

- **ArgoCD UI:** https://argocd.example.com
- **Traefik Dashboard:** https://traefik.example.com
- **Linkerd Dashboard:** https://linkerd.example.com

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

# AWS
export AWS_REGION=us-east-1
export AWS_PROFILE=default

# Kubernetes
export KUBECONFIG=~/.kube/config
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

alias awssm='aws secretsmanager'
alias awssm-list='aws secretsmanager list-secrets --region us-east-1'
alias awssm-get='aws secretsmanager get-secret-value --region us-east-1 --secret-id'
```

## Secret Management Cheat Sheet

```bash
# Create secret
aws secretsmanager create-secret \
  --name <env>/<app>/<name> \
  --secret-string '{"key":"value"}' \
  --region us-east-1

# Update secret
aws secretsmanager update-secret \
  --secret-id <env>/<app>/<name> \
  --secret-string '{"key":"new-value"}' \
  --region us-east-1

# Get secret
aws secretsmanager get-secret-value \
  --secret-id <env>/<app>/<name> \
  --region us-east-1

# Delete secret (30-day recovery window)
aws secretsmanager delete-secret \
  --secret-id <env>/<app>/<name> \
  --region us-east-1

# Restore deleted secret
aws secretsmanager restore-secret \
  --secret-id <env>/<app>/<name> \
  --region us-east-1

# Force delete (no recovery)
aws secretsmanager delete-secret \
  --secret-id <env>/<app>/<name> \
  --force-delete-without-recovery \
  --region us-east-1
```

## CSI Driver Troubleshooting Cheat Sheet

```bash
# Check CSI Driver health
kubectl get pods -n kube-system | grep csi
kubectl get daemonset -n kube-system secrets-store-csi-driver
kubectl get csidriver secrets-store.csi.k8s.io

# View CSI Driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=100

# View AWS Provider logs
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws --tail=100

# List SecretProviderClass in all namespaces
kubectl get secretproviderclass -A

# Check if secret is mounted in pod
kubectl exec -n <namespace> <pod> -- ls -la /mnt/secrets
kubectl exec -n <namespace> <pod> -- cat /mnt/secrets/<secret-file>

# Check if Kubernetes Secret is synced
kubectl get secret <name> -n <namespace>
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | jq

# Check pod events for CSI errors
kubectl describe pod <pod> -n <namespace> | grep -A 30 Events

# Test IRSA from pod
kubectl run aws-test --rm -it --image=amazon/aws-cli \
  --serviceaccount=<sa-name> -n <namespace> -- \
  secretsmanager list-secrets --region us-east-1
```

## ArgoCD Sync Strategies

```bash
# Auto-sync (automatic deployment)
argocd app set <app-name> --sync-policy automated

# Manual sync only
argocd app set <app-name> --sync-policy none

# Enable auto-prune (delete resources not in Git)
argocd app set <app-name> --auto-prune

# Enable self-heal (revert manual changes)
argocd app set <app-name> --self-heal

# Sync with prune
argocd app sync <app-name> --prune

# Sync specific resource
argocd app sync <app-name> --resource :Deployment:my-app
```

---

**Pro Tip:** Keep this guide bookmarked for quick access during incidents!

**Last Updated:** 2025-12-02
**Platform Version:** 2.0.0 (AWS Secrets Manager)
