# Getting Started Guide

## 🚀 Quick Start

Get the platform running in **under 10 minutes**.

### Prerequisites

**Required Tools:**
```bash
# Install via Homebrew (macOS/Linux)
brew install kubectl helm aws-cli argocd terraform jq yq
```

**AWS Resources:**
- **AWS CLI** configured (`aws configure`)
- **EKS Cluster** (v1.28+) with OIDC provider enabled
- **ECR Repository** for images and charts

### One-Command Deployment
```bash
./deploy.sh
```
This script updates placeholders, creates secrets, installs infrastructure, and deploys services.

---

## 📋 Deployment Checklist

### 1. Pre-Deployment
- [ ] Clone repository
- [ ] Update values in `charts/vsf-miniapp/ci/*.yaml` (ECR URL, Account ID)
- [ ] Create AWS Secrets (see Configuration section)
- [ ] Create IAM Roles with IRSA (see Configuration section)

### 2. Infrastructure
- [ ] Run `./bootstrap/install.sh`
- [ ] Verify pods in `argocd`, `linkerd`, `traefik`, `kube-system` namespaces

### 3. Application Deployment
- [ ] Deploy Dev: `argocd app sync vsf-miniapp-service-a-dev`
- [ ] Verify Linkerd mTLS: `linkerd viz stat deployment -n dev`
- [ ] Deploy Staging/Prod after verification

---

## ⚙️ Configuration Guide

### 1. Update Placeholders
Find and replace these values in `charts/vsf-miniapp/ci/`:
- `YOUR_ECR_REGISTRY` -> e.g., `123456789012.dkr.ecr.us-east-1.amazonaws.com`
- `ACCOUNT_ID` -> e.g., `123456789012`
- `vsf-miniapp.com` -> Your actual domain

### 2. Create Required AWS Secrets
**Service A (Java):**
```bash
aws secretsmanager create-secret --name dev/vsf-miniapp/service-a/database \
  --secret-string '{"url":"jdbc:postgresql://...","username":"user","password":"pw"}'
```

**Service B (Node.js):**
```bash
aws secretsmanager create-secret --name dev/vsf-miniapp/service-b/mongodb \
  --secret-string '{"connectionString":"mongodb://...","database":"db"}'
```

### 3. IAM Roles (IRSA)
Ensure IAM roles exist and trust the EKS OIDC provider.
```bash
eksctl create iamserviceaccount --name service-a --namespace dev \
  --cluster gitops-eks-cluster --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite --approve
```

---

## 📖 Detailed Manual Deployment Steps

If you prefer not to use the `deploy.sh` script, follow these phases manually.

### Phase 1: Deploy Infrastructure via Terraform (Optional)
If you haven't created IAM roles yet:
```bash
cd terraform
terraform init && terraform apply -auto-approve
export CSI_DRIVER_ROLE_ARN=$(terraform output -raw csi_driver_role_arn)
```

### Phase 2: Bootstrap ArgoCD
```bash
# Connect to EKS
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1

# Install ArgoCD and Root App
./bootstrap/install.sh
```

### Phase 3: Configure Linkerd Certificates
```bash
cd infrastructure/linkerd
./generate-certs.sh
# This generates CA and Issuer certs and applies them to the cluster
```

### Phase 4: Verify Infrastructure Sync
Check that ArgoCD has synced the infrastructure components:
```bash
kubectl get application -n argocd | grep infrastructure
# Should show: secrets-store-csi, traefik, linkerd, reloader as Synced/Healthy
```

### Phase 5: Deploy Applications
Deploy the Development environment:
```bash
# Apply App of Apps for Dev
kubectl apply -f applications/app-of-apps-dev.yaml

# Sync Service A
argocd app sync vsf-miniapp-service-a-dev
```

### Phase 6: Verify Success
```bash
# Check pods
kubectl get pods -n dev
# Check mTLS
linkerd viz stat deployment -n dev
# Check Secrets
kubectl exec -n dev deploy/service-a -- ls -la /mnt/secrets
```