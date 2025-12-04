# Deployment Instructions - VSF-Miniapp Multi-Service Platform

## 🎯 Current Status

✅ **Multi-service architecture implemented**
✅ **Pushed to GitHub**: `feature/multi-service-architecture` branch
✅ **Services ready**: Service A (Java), Service B (Node.js)
✅ **All configurations validated**

**GitHub Branch**: https://github.com/oNddleo/gitops/tree/feature/multi-service-architecture

**Pull Request**: https://github.com/oNddleo/gitops/pull/new/feature/multi-service-architecture

---

## 📋 Pre-Deployment Checklist

### 1. Update Configuration (REQUIRED)

Before deploying, update placeholder values:

```bash
# Set your actual values
export ECR_REGISTRY="YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com"
export AWS_ACCOUNT_ID="YOUR_ACCOUNT_ID"
export DOMAIN="your-domain.com"

# Update all placeholders
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|YOUR_ECR_REGISTRY|${ECR_REGISTRY}|g" {} \;
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" {} \;
find charts/vsf-miniapp/ci/ -name "*-production.yaml" -exec sed -i "s|vsf-miniapp.com|${DOMAIN}|g" {} \;

# Commit the updates
git add charts/vsf-miniapp/ci/
git commit -m "chore: update ECR registry and AWS account ID"
git push origin feature/multi-service-architecture
```

**See [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) for detailed instructions.**

---

### 2. Create AWS Secrets (REQUIRED)

**Before deploying**, create secrets in AWS Secrets Manager:

#### Quick Start - Development Only

```bash
# Service A - Dev Database
aws secretsmanager create-secret \
  --name dev/vsf-miniapp/service-a/database \
  --secret-string '{
    "url": "postgresql://localhost:5432/servicea",
    "username": "dev_user",
    "password": "dev_password"
  }' \
  --region us-east-1

# Service B - Dev MongoDB
aws secretsmanager create-secret \
  --name dev/vsf-miniapp/service-b/mongodb \
  --secret-string '{
    "connectionString": "mongodb://localhost:27017/serviceb",
    "database": "serviceb"
  }' \
  --region us-east-1
```

**For all secrets**, see [CONFIGURATION_GUIDE.md § AWS Secrets Manager Secrets](CONFIGURATION_GUIDE.md#3-aws-secrets-manager-secrets)

---

### 3. Create IAM Roles (REQUIRED)

Create IRSA roles for each service:

```bash
# Service A - Dev
eksctl create iamserviceaccount \
  --name service-a \
  --namespace dev \
  --cluster gitops-eks-cluster \
  --role-name vsf-miniapp-service-a-dev-secrets-reader \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve \
  --region us-east-1

# Service B - Dev
eksctl create iamserviceaccount \
  --name service-b \
  --namespace dev \
  --cluster gitops-eks-cluster \
  --role-name vsf-miniapp-service-b-dev-secrets-reader \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve \
  --region us-east-1
```

**Note:** Replace with least-privilege policies in production.

---

### 4. Merge to Master (Optional)

You can deploy from the feature branch or merge to master:

```bash
# Option 1: Merge to master
git checkout master
git merge feature/multi-service-architecture
git push origin master

# Option 2: Deploy from feature branch (ArgoCD will track it)
# Just push your feature branch (already done)
```

---

## 🚀 Deployment Steps

### Step 1: Connect to Your Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1

# Verify connection
kubectl cluster-info
kubectl get nodes
```

---

### Step 2: Verify Infrastructure is Running

```bash
# Check ArgoCD
kubectl get pods -n argocd
argocd app list

# Check Linkerd
linkerd check
kubectl get pods -n linkerd

# Check Secrets Store CSI Driver
kubectl get pods -n kube-system | grep csi
kubectl get pods -n kube-system | grep secrets-store

# Check Traefik
kubectl get pods -n traefik

# Check Reloader
kubectl get pods -n reloader
```

**If any infrastructure component is missing**, deploy it first using the bootstrap:

```bash
./bootstrap/install.sh
```

---

### Step 3: Deploy Service A to Dev

ArgoCD will automatically detect the new applications if you're using the App of Apps pattern.

```bash
# List applications
argocd app list | grep vsf-miniapp

# Sync Service A to dev
argocd app sync vsf-miniapp-service-a-dev

# Wait for deployment
argocd app wait vsf-miniapp-service-a-dev --health --timeout 300

# Check status
argocd app get vsf-miniapp-service-a-dev
```

**Verify deployment:**

```bash
# Check pods
kubectl get pods -n dev -l service=service-a

# Check secrets
kubectl get secret service-a-secrets -n dev
kubectl describe secret service-a-secrets -n dev

# Check CSI volume mount
POD=$(kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dev $POD -- ls -la /mnt/secrets/

# Check service
kubectl get svc -n dev -l service=service-a

# Check ingress
kubectl get ingressroute -n dev
```

---

### Step 4: Verify Linkerd mTLS

```bash
# Check proxy injection
kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].spec.containers[*].name}'
# Expected: service-a linkerd-proxy

# Check mTLS status
linkerd viz stat deployment -n dev
# Expected: All deployments show "SECURED"

# View live traffic
linkerd viz tap deployment/service-a-vsf-miniapp-service-a -n dev

# Check service topology
linkerd viz edges deployment -n dev
```

---

### Step 5: Deploy Service B to Dev

```bash
# Sync Service B
argocd app sync vsf-miniapp-service-b-dev

# Wait for deployment
argocd app wait vsf-miniapp-service-b-dev --health --timeout 300

# Verify
kubectl get pods -n dev -l service=service-b
kubectl get secret service-b-secrets -n dev
```

---

### Step 6: Test Service-to-Service Communication with mTLS

```bash
# Get Service A pod
POD_A=$(kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].metadata.name}')

# Test calling Service B from Service A (HTTP - Linkerd handles mTLS)
kubectl exec -n dev $POD_A -c service-a -- \
  curl -s http://service-b-vsf-miniapp-service-b.dev.svc.cluster.local/health/ready

# Expected: {"status":"ok"} or similar health check response

# Check mTLS in Linkerd Viz
linkerd viz tap deployment/service-a-vsf-miniapp-service-a -n dev | grep service-b
# Should show encrypted traffic with TLS status
```

---

### Step 7: Deploy to Staging

Once dev is stable:

```bash
# Sync both services to staging
argocd app sync vsf-miniapp-service-a-staging
argocd app sync vsf-miniapp-service-b-staging

# Wait for deployments
argocd app wait vsf-miniapp-service-a-staging --health --timeout 300
argocd app wait vsf-miniapp-service-b-staging --health --timeout 300

# Verify
kubectl get pods -n staging
linkerd viz stat deployment -n staging
```

---

### Step 8: Deploy to Production

**IMPORTANT:** Only after staging is verified!

```bash
# Sync both services to production
argocd app sync vsf-miniapp-service-a-production
argocd app sync vsf-miniapp-service-b-production

# Wait for deployments
argocd app wait vsf-miniapp-service-a-production --health --timeout 300
argocd app wait vsf-miniapp-service-b-production --health --timeout 300

# Verify pods are distributed across AZs
kubectl get pods -n production -o wide -l service=service-a
kubectl get pods -n production -o wide -l service=service-b

# Check HPA is working
kubectl get hpa -n production

# Verify Linkerd mTLS
linkerd viz stat deployment -n production
```

---

## 📊 What Was Deployed

### Services

| Service | Language | Port | Health | Secrets | Replicas (Dev/Staging/Prod) |
|---------|----------|------|--------|---------|----------------------------|
| **Service A** | Java Spring Boot | 8080 | `/actuator/health` | PostgreSQL, Kafka | 1 / 2-5 / 5-20 |
| **Service B** | Node.js Express | 3000 | `/health/ready` | MongoDB, Redis, JWT | 1 / 2-5 / 3-15 |

### Infrastructure

✅ **Linkerd mTLS** - All service-to-service traffic encrypted
✅ **AWS Secrets Manager** - Secrets mounted via CSI driver
✅ **Reloader** - Auto-restart on secret/config changes
✅ **Traefik** - Ingress with IngressRoute CRDs
✅ **HPA** - Auto-scaling in staging/production
✅ **Multi-AZ** - Pod anti-affinity in production

---

## 🔍 Monitoring & Troubleshooting

### Check Application Status

```bash
# ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Visit https://localhost:8080

# Linkerd Viz
linkerd viz dashboard
# Opens browser with live metrics

# Check all applications
argocd app list
kubectl get applications -n argocd
```

### Common Issues

#### Issue: Pods stuck in "Init:0/1"

**Cause:** Secrets not found in AWS Secrets Manager or IRSA not working

**Fix:**
```bash
# Check SecretProviderClass
kubectl describe secretproviderclass -n dev

# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Test IRSA permissions
kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=service-a -n dev -- \
  secretsmanager get-secret-value --secret-id dev/vsf-miniapp/service-a/database --region us-east-1
```

#### Issue: mTLS not working

**Cause:** Linkerd proxy not injected or control plane not running

**Fix:**
```bash
# Check Linkerd
linkerd check

# Check pod annotations
kubectl get pod <pod-name> -n dev -o yaml | grep linkerd

# Restart pods
kubectl rollout restart deployment/service-a-vsf-miniapp-service-a -n dev
```

#### Issue: Services can't communicate

**Cause:** Service names or DNS not resolving

**Fix:**
```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup service-b-vsf-miniapp-service-b.dev.svc.cluster.local

# Check service exists
kubectl get svc -n dev

# Check network policies (shouldn't block with Linkerd)
kubectl get networkpolicies -n dev
```

---

## 📈 Next Steps

1. **Add CI/CD Pipeline** - Update `.github/workflows/` to build Docker images
2. **Add More Services** - Copy service-b pattern for service-c, service-d
3. **Configure Monitoring** - Set up Prometheus/Grafana dashboards
4. **Set up Alerts** - Configure ArgoCD notifications to Slack
5. **Implement Canary Deployments** - Use Flagger with Linkerd

---

## 📚 Additional Resources

- [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) - Configuration reference
- [MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md) - Quick reference
- [ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md) - Detailed architecture
- [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md) - Visual diagrams

---

## ✅ Success Criteria

Your deployment is successful when:

- [ ] All pods in `Running` state
- [ ] All ArgoCD applications `Healthy` and `Synced`
- [ ] Secrets mounted in `/mnt/secrets/`
- [ ] Linkerd shows "SECURED" for all services
- [ ] Service-to-service calls work
- [ ] Health checks passing
- [ ] Ingress routes accessible
- [ ] HPA creating/removing pods based on load

**Congratulations! You have a production-ready multi-service GitOps platform!** 🎉
