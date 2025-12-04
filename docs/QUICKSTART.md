# VSF-Miniapp Quick Start Guide

Get your multi-service platform running in **under 10 minutes**.

---

## 🚀 One-Command Deployment

```bash
./deploy.sh
```

This interactive script will:
1. ✅ Update configuration placeholders
2. ✅ Create AWS Secrets Manager secrets
3. ✅ Connect to your Kubernetes cluster
4. ✅ Verify infrastructure components
5. ✅ Deploy both services to dev
6. ✅ Show verification commands

---

## 📋 Prerequisites

Before running `./deploy.sh`, ensure you have:

- [ ] **AWS CLI** configured with credentials
- [ ] **kubectl** installed and configured
- [ ] **ArgoCD CLI** installed (optional, for manual sync)
- [ ] **EKS cluster** with OIDC provider enabled
- [ ] **Infrastructure deployed** (Linkerd, Traefik, CSI Driver, ArgoCD)

### Install Infrastructure (If Not Already Done)

```bash
./bootstrap/install.sh
```

---

## 🎯 What You're Deploying

### Services

| Service | Type | Port | Replicas (Dev) | Secrets |
|---------|------|------|----------------|---------|
| **Service A** | Java Spring Boot | 8080 | 1 | PostgreSQL |
| **Service B** | Node.js Express | 3000 | 1 | MongoDB |

### Features

✅ **Linkerd mTLS** - Automatic encryption
✅ **AWS Secrets Manager** - Secure secret storage
✅ **Auto-scaling** - HPA enabled in staging/prod
✅ **Auto-reload** - Reloader watches config changes
✅ **GitOps** - ArgoCD manages deployments

---

## 📖 Manual Deployment (Alternative to ./deploy.sh)

### Step 1: Update Configuration (2 minutes)

```bash
# Set your values
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
export AWS_ACCOUNT_ID="123456789012"

# Update files
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|YOUR_ECR_REGISTRY|${ECR_REGISTRY}|g" {} \;
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" {} \;

# Commit
git add charts/vsf-miniapp/ci/
git commit -m "chore: update configuration"
git push
```

### Step 2: Create Secrets (3 minutes)

```bash
# Service A - Dev
aws secretsmanager create-secret \
  --name dev/vsf-miniapp/service-a/database \
  --secret-string '{"url":"postgresql://localhost:5432/servicea","username":"dev","password":"dev"}' \
  --region us-east-1

# Service B - Dev
aws secretsmanager create-secret \
  --name dev/vsf-miniapp/service-b/mongodb \
  --secret-string '{"connectionString":"mongodb://localhost:27017/serviceb","database":"serviceb"}' \
  --region us-east-1
```

### Step 3: Deploy (2 minutes)

```bash
# Connect to cluster
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1

# Sync applications (or wait for auto-sync)
argocd app sync vsf-miniapp-service-a-dev
argocd app sync vsf-miniapp-service-b-dev

# Verify
kubectl get pods -n dev
```

---

## ✅ Verification

### Check Deployments

```bash
# Pods should be Running
kubectl get pods -n dev

# Expected output:
# service-a-vsf-miniapp-service-a-xxxxx   2/2   Running
# service-b-vsf-miniapp-service-b-xxxxx   2/2   Running
```

### Verify Linkerd mTLS

```bash
linkerd viz stat deployment -n dev

# Expected: All deployments show "SECURED"
```

### Test Service Communication

```bash
# Get Service A pod
POD_A=$(kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].metadata.name}')

# Call Service B from Service A
kubectl exec -n dev $POD_A -c service-a -- \
  curl -s http://service-b-vsf-miniapp-service-b.dev.svc.cluster.local/health/ready

# Should return: {"status":"ok"} or similar
```

### Check Secrets

```bash
# Secrets should exist
kubectl get secrets -n dev | grep service-

# Check mounted secrets
kubectl exec -n dev $POD_A -c service-a -- ls -la /mnt/secrets/
```

---

## 🎛️ ArgoCD UI

Access ArgoCD dashboard:

```bash
# Port forward
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Open browser: https://localhost:8080
# Username: admin
# Password: (from above command)
```

---

## 📊 Linkerd Dashboard

View real-time mTLS metrics:

```bash
linkerd viz dashboard

# Opens browser with:
# - Service topology
# - Live traffic
# - mTLS status
# - Success rates
```

---

## 🚀 Deploy to Staging/Production

Once dev is verified:

```bash
# Staging
argocd app sync vsf-miniapp-service-a-staging
argocd app sync vsf-miniapp-service-b-staging

# Production (after staging verification)
argocd app sync vsf-miniapp-service-a-production
argocd app sync vsf-miniapp-service-b-production
```

**Note:** Remember to create staging/production secrets first!

---

## 🔧 Troubleshooting

### Pods stuck in Init

**Problem:** Pods show `Init:0/1`

**Solution:** Check secrets exist in AWS Secrets Manager

```bash
aws secretsmanager get-secret-value \
  --secret-id dev/vsf-miniapp/service-a/database \
  --region us-east-1
```

### Linkerd not showing SECURED

**Problem:** mTLS not working

**Solution:** Check Linkerd proxy injection

```bash
kubectl get pod -n dev -l service=service-a -o yaml | grep linkerd.io/inject
# Should show: linkerd.io/inject: enabled

# Restart deployment
kubectl rollout restart deployment/service-a-vsf-miniapp-service-a -n dev
```

### ArgoCD app not syncing

**Problem:** Application shows OutOfSync

**Solution:** Force refresh and sync

```bash
argocd app refresh vsf-miniapp-service-a-dev --hard
argocd app sync vsf-miniapp-service-a-dev --prune
```

---

## 📚 Full Documentation

- **[DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)** - Detailed deployment guide
- **[CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md)** - All configuration options
- **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** - Quick reference
- **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** - Architecture deep dive

---

## 💡 Tips

### Add a New Service

```bash
# Copy existing service config
cp charts/vsf-miniapp/ci/service-b-production.yaml \
   charts/vsf-miniapp/ci/service-c-production.yaml

# Edit serviceName, ports, secrets
vim charts/vsf-miniapp/ci/service-c-production.yaml

# Copy ArgoCD app
cp applications/production/vsf-miniapp-service-b.yaml \
   applications/production/vsf-miniapp-service-c.yaml

# Update references
sed -i 's/service-b/service-c/g' applications/production/vsf-miniapp-service-c.yaml

# Commit and push - ArgoCD will deploy automatically!
```

### View Logs

```bash
# Service A logs
kubectl logs -n dev -l service=service-a -c service-a --tail=100 -f

# Service B logs
kubectl logs -n dev -l service=service-b -c service-b --tail=100 -f

# Linkerd proxy logs
kubectl logs -n dev -l service=service-a -c linkerd-proxy --tail=50
```

### Scale Manually

```bash
# Scale Service A to 3 replicas
kubectl scale deployment/service-a-vsf-miniapp-service-a -n dev --replicas=3

# Note: HPA will override this in staging/production
```

---

## 🎉 Success!

When you see:

- ✅ All pods `Running`
- ✅ ArgoCD apps `Healthy` and `Synced`
- ✅ Linkerd showing `SECURED`
- ✅ Services can communicate

**You have a production-ready multi-service GitOps platform!** 🚀

---

## 🆘 Need Help?

1. Check **[DEPLOYMENT_INSTRUCTIONS.md](DEPLOYMENT_INSTRUCTIONS.md)** for detailed steps
2. Review **[CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md)** for configuration
3. See **[MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md)** for troubleshooting
4. Open an issue on GitHub

---

**Estimated time to production: 10 minutes** ⏱️

Happy deploying! 🎊
