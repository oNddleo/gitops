# Implementation Plan: AWS Secrets Manager with CSI Driver

This document provides a comprehensive implementation plan for deploying AWS Secrets Manager integration using the Kubernetes Secrets Store CSI Driver.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Implementation Steps](#implementation-steps)
5. [Deployment Order](#deployment-order)
6. [Testing & Validation](#testing--validation)
7. [Operational Procedures](#operational-procedures)

---

## Overview

### Objective

Replace self-hosted HashiCorp Vault with AWS Secrets Manager to reduce operational overhead while maintaining secure secrets management for the GitOps platform.

### Key Changes

| Component | Before | After |
|-----------|--------|-------|
| **Secrets Storage** | HashiCorp Vault on EKS | AWS Secrets Manager (fully managed) |
| **Secrets Sync** | External Secrets Operator | Secrets Store CSI Driver |
| **Infrastructure** | Vault pods + DynamoDB + S3 + KMS | CSI Driver pods only |
| **IAM Integration** | Vault IRSA for AWS backend | IRSA for Secrets Manager API |
| **Operational Overhead** | High (Vault HA, backups, upgrades) | Minimal (AWS-managed) |

### Success Criteria

- ✅ All applications can retrieve secrets from AWS Secrets Manager
- ✅ Secrets are automatically rotated via CSI Driver (2-minute poll interval)
- ✅ Reloader triggers rolling updates when secrets change
- ✅ No manual `kubectl` commands needed for secret management
- ✅ Zero Vault infrastructure running
- ✅ Cost reduced by 70-80%

---

## Architecture

### High-Level Flow

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
┌──────────────────────────────┐
│ Pod with CSI Volume          │
│  ├── /mnt/secrets/db-url     │ ← Mounted as files
│  ├── /mnt/secrets/db-pass    │
│  └── env: DATABASE_URL       │ ← From synced K8s Secret
└──────────────────────────────┘
       ↓
Reloader watches Secret changes
       ↓
Triggers rolling update
```

### Components

1. **AWS Secrets Manager**: Centralized secret storage (AWS-managed)
2. **Secrets Store CSI Driver**: Kubernetes CSI driver for secret mounting
3. **AWS Provider**: AWS-specific provider for the CSI driver
4. **SecretProviderClass**: CRD defining which secrets to retrieve
5. **IRSA (IAM Roles for Service Accounts)**: AWS IAM integration for pods
6. **Reloader**: Watches synced Kubernetes Secrets and triggers pod updates

---

## Prerequisites

### AWS Requirements

- [ ] AWS Account with admin access
- [ ] EKS cluster (v1.28+) with OIDC provider enabled
- [ ] AWS CLI configured with appropriate credentials
- [ ] Terraform v1.0+ installed

### Kubernetes Requirements

- [ ] kubectl configured to access the cluster
- [ ] ArgoCD installed and operational
- [ ] Helm v3.14+ installed
- [ ] Cluster has internet access (for Helm chart pulls)

### Permissions Required

- [ ] IAM permissions to create roles and policies
- [ ] EKS cluster admin access
- [ ] Secrets Manager read/write permissions
- [ ] ArgoCD admin access

---

## Implementation Steps

### Step 1: Deploy Terraform Infrastructure

**Duration**: 30 minutes
**Risk**: Low
**Rollback**: Yes

```bash
cd terraform

# Create or update main.tf with IRSA module
cat > main.tf <<'EOF'
provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "gitops-eks-cluster"
}

data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

module "secrets_manager_irsa" {
  source = "./modules/secrets-manager-irsa"

  cluster_name       = var.cluster_name
  oidc_provider_url  = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
  namespace          = "kube-system"
  service_account_name = "secrets-store-csi-driver"
  secret_prefix      = "*"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "gitops-platform"
  }
}

output "csi_driver_role_arn" {
  description = "IAM role ARN for Secrets Store CSI Driver"
  value       = module.secrets_manager_irsa.role_arn
}
EOF

# Initialize and apply
terraform init
terraform plan
terraform apply -auto-approve

# Capture the role ARN
export CSI_DRIVER_ROLE_ARN=$(terraform output -raw csi_driver_role_arn)
echo "CSI Driver Role ARN: $CSI_DRIVER_ROLE_ARN"
```

**Validation**:
```bash
aws iam get-role --role-name gitops-eks-cluster-secrets-csi-driver
aws iam list-attached-role-policies --role-name gitops-eks-cluster-secrets-csi-driver
```

---

### Step 2: Update Infrastructure Manifests

**Duration**: 15 minutes
**Risk**: Low
**Rollback**: Yes (Git revert)

```bash
# Update CSI Driver kustomization with IAM role ARN
sed -i "s|arn:aws:iam::ACCOUNT_ID:role/[^\"]*|${CSI_DRIVER_ROLE_ARN}|g" \
  infrastructure/secrets-store-csi/kustomization.yaml

# Update region if needed
sed -i 's|region: us-east-1|region: YOUR_REGION|g' \
  infrastructure/secrets-store-csi/example-secretproviderclass.yaml

# Review changes
git diff infrastructure/secrets-store-csi/

# Commit
git add infrastructure/secrets-store-csi/
git commit -m "feat: configure secrets-store-csi with IAM role"
git push origin main
```

---

### Step 3: Deploy CSI Driver via ArgoCD

**Duration**: 15 minutes
**Risk**: Low
**Rollback**: Yes (delete ArgoCD app)

```bash
# Verify infrastructure-apps.yaml includes secrets-store-csi
cat applications/infrastructure-apps.yaml | grep -A 20 "secrets-store-csi"

# Apply the updated infrastructure apps
argocd app sync infrastructure-apps

# Wait for sync
argocd app wait secrets-store-csi --health --timeout 300

# Verify CSI Driver is running
kubectl get pods -n kube-system | grep csi
kubectl get daemonset -n kube-system | grep secrets-store
kubectl get csidriver secrets-store.csi.k8s.io
```

**Expected Output**:
```
secrets-store-csi-driver-xxxxx           3/3     Running
csi-secrets-store-provider-aws-xxxxx     1/1     Running

NAME                          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
secrets-store-csi-driver      3         3         3       3            3

NAME                          ATTACHREQUIRED   PODINFOONMOUNT   MODES
secrets-store.csi.k8s.io     false            true             file
```

---

### Step 4: Create Secrets in AWS Secrets Manager

**Duration**: 30-60 minutes
**Risk**: Low
**Rollback**: Yes (delete secrets)

```bash
# Create production secrets
aws secretsmanager create-secret \
  --name production/myapp/database \
  --description "Production database credentials" \
  --secret-string '{"url":"postgresql://prod-db.example.com:5432/myapp","username":"app_user","password":"CHANGE_ME"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=production Key=Application,Value=myapp

# Create API key secret
aws secretsmanager create-secret \
  --name production/myapp/api-key \
  --description "Production API key" \
  --secret-string "prod-api-key-12345" \
  --region us-east-1 \
  --tags Key=Environment,Value=production Key=Application,Value=myapp

# Staging secrets
aws secretsmanager create-secret \
  --name staging/myapp/database \
  --description "Staging database credentials" \
  --secret-string '{"url":"postgresql://staging-db.example.com:5432/myapp","username":"app_user","password":"CHANGE_ME"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=staging

# Development secrets
aws secretsmanager create-secret \
  --name development/myapp/database \
  --description "Development database credentials" \
  --secret-string '{"url":"postgresql://dev-db.example.com:5432/myapp","username":"app_user","password":"CHANGE_ME"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=development

# List all created secrets
aws secretsmanager list-secrets --region us-east-1 --output table
```

---

### Step 5: Update Application Helm Charts

**Duration**: 30 minutes
**Risk**: Low (only updates manifests, not deployed yet)
**Rollback**: Yes (Git revert)

```bash
# Update Chart.yaml and values.yaml are already updated with:
# - secretproviderclass.yaml template
# - deployment.yaml with CSI volume mount
# - serviceAccount with IRSA annotation
# - values.yaml with secretsManager configuration

# Update environment-specific values
for env in dev staging production; do
  vim charts/my-microservice/ci/${env}-values.yaml

  # Add/update:
  # secretsManager:
  #   enabled: true
  #   region: us-east-1
  #   ...

  # serviceAccount:
  #   annotations:
  #     eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/..."
done

# Commit changes
git add charts/my-microservice/
git commit -m "feat: migrate application to use AWS Secrets Manager via CSI"
git push origin main
```

---

### Step 6: Deploy to Development Environment

**Duration**: 30 minutes
**Risk**: Medium
**Rollback**: Yes (ArgoCD rollback)

```bash
# Sync development application
argocd app sync my-microservice-dev

# Watch deployment
kubectl get pods -n development -w

# Verify SecretProviderClass created
kubectl get secretproviderclass -n development
kubectl describe secretproviderclass my-microservice-secrets -n development

# Check secrets mounted in pod
POD=$(kubectl get pods -n development -l app=my-microservice -o name | head -1)
kubectl exec -n development $POD -- ls -la /mnt/secrets

# Verify Kubernetes Secret synced
kubectl get secret my-microservice-secrets -n development
kubectl describe secret my-microservice-secrets -n development

# Check application logs
kubectl logs -n development $POD --tail=50

# Test application
kubectl port-forward -n development svc/my-microservice 8080:80
curl http://localhost:8080/health
```

---

### Step 7: Deploy to Staging Environment

**Duration**: 30 minutes
**Risk**: Medium
**Rollback**: Yes

```bash
# Sync staging application
argocd app sync my-microservice-staging
argocd app wait my-microservice-staging --health --timeout 300

# Validation (same as development)
kubectl get pods -n staging
kubectl get secretproviderclass -n staging
kubectl exec -n staging <pod> -- ls -la /mnt/secrets
kubectl get secret my-microservice-secrets -n staging
```

---

### Step 8: Deploy to Production Environment

**Duration**: 1 hour (including monitoring)
**Risk**: High
**Rollback**: Yes (but may cause brief downtime)

**Pre-deployment checklist**:
- [ ] Dev and Staging deployments successful
- [ ] All tests passing
- [ ] Monitoring and alerting configured
- [ ] Rollback plan documented
- [ ] Team notified of deployment

```bash
# Sync production application
argocd app sync my-microservice-production

# Monitor closely
kubectl get pods -n production -w

# For each pod, verify:
for pod in $(kubectl get pods -n production -l app=my-microservice -o name); do
  echo "=== Checking $pod ==="
  kubectl exec -n production $pod -- ls -la /mnt/secrets
  kubectl logs -n production $pod --tail=20
  echo ""
done

# Verify service health
kubectl get svc -n production
curl https://myapp.example.com/health

# Check metrics/monitoring
kubectl top pods -n production
```

---

## Deployment Order

### Infrastructure Deployment

1. ✅ Terraform (IAM roles)
2. ✅ Update manifests (IAM ARNs)
3. ✅ Deploy CSI Driver (ArgoCD)
4. ✅ Create secrets (AWS Secrets Manager)

### Application Deployment

1. ✅ Update Helm charts
2. ✅ Deploy to Development
3. ✅ Validate and test
4. ✅ Deploy to Staging
5. ✅ Validate and test
6. ✅ Deploy to Production
7. ✅ Monitor and validate

### Cleanup (after successful migration)

1. ✅ Remove Vault application (ArgoCD)
2. ✅ Remove External Secrets application (ArgoCD)
3. ✅ Delete Vault infrastructure (AWS resources)
4. ✅ Archive Vault backups

---

## Testing & Validation

### Functional Tests

```bash
# Test secret mounting
kubectl exec -n production <pod> -- cat /mnt/secrets/database-url

# Test environment variables (from synced Secret)
kubectl exec -n production <pod> -- env | grep DATABASE

# Test application functionality
curl https://myapp.example.com/api/test

# Test database connectivity
kubectl exec -n production <pod> -- nc -zv prod-db.example.com 5432
```

### Secret Rotation Test

```bash
# Update secret in AWS
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '{"url":"postgresql://prod-db:5432/myapp","username":"app_user","password":"NEW_PASSWORD"}' \
  --region us-east-1

# Wait for CSI Driver to sync (2 minutes)
sleep 120

# Verify file updated
kubectl exec -n production <pod> -- cat /mnt/secrets/database-password

# Verify Kubernetes Secret updated
kubectl get secret my-microservice-secrets -n production -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d

# Reloader should trigger rolling update
kubectl get events -n production --sort-by='.lastTimestamp' | grep Reloader
kubectl get pods -n production -w
```

### Performance Tests

```bash
# Check pod startup time
kubectl delete pod <pod-name> -n production
time kubectl wait --for=condition=ready pod/<new-pod-name> -n production --timeout=300s

# Check CSI driver overhead
kubectl top pod -n kube-system | grep csi

# Check secret fetch latency
kubectl logs -n kube-system -l app=secrets-store-csi-driver | grep latency
```

---

## Operational Procedures

### Daily Operations

```bash
# Check CSI Driver health
kubectl get pods -n kube-system | grep csi
kubectl get daemonset -n kube-system secrets-store-csi-driver

# List all SecretProviderClasses
kubectl get secretproviderclass -A

# View secret usage
aws secretsmanager list-secrets --region us-east-1
```

### Creating New Secrets

```bash
# 1. Create in AWS Secrets Manager
aws secretsmanager create-secret \
  --name production/newapp/config \
  --secret-string '{"key":"value"}' \
  --region us-east-1

# 2. Update SecretProviderClass in Helm values
# 3. Commit and push
git add charts/newapp/
git commit -m "feat: add secrets for newapp"
git push

# 4. ArgoCD will auto-sync
argocd app sync newapp-production
```

### Updating Secrets

```bash
# Update in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '{"url":"...","password":"NEW_VALUE"}' \
  --region us-east-1

# CSI Driver syncs automatically (2-minute poll)
# Reloader triggers rolling update automatically
# No manual intervention needed!
```

### Monitoring

```bash
# CSI Driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=100 -f

# AWS Provider logs
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws --tail=100 -f

# SecretProviderClass events
kubectl get events -A | grep ProviderVolume

# Reloader logs
kubectl logs -n reloader -l app=reloader --tail=100 -f
```

---

## Success Metrics

### Operational Metrics

- **Mean Time to Deploy**: < 5 minutes (same as before)
- **Secret Rotation Time**: < 5 minutes (CSI poll + Reloader)
- **Infrastructure Cost**: Reduced by 70-80%
- **Operational Overhead**: Reduced by 90%+

### Technical Metrics

- **CSI Driver Uptime**: > 99.9%
- **Secret Fetch Success Rate**: > 99.9%
- **Pod Startup Time**: < 30 seconds (no significant change)
- **Secret Sync Latency**: < 2 minutes

---

## Support and Escalation

### Common Issues

| Issue | Solution |
|-------|----------|
| Secret not mounting | Check IRSA permissions, SecretProviderClass config |
| Pod fails to start | Check CSI driver logs, verify secret exists in AWS |
| Secret not syncing | Verify rotationPollInterval, check CSI driver health |
| Reloader not triggering | Verify annotation on synced Secret |

### Escalation Path

1. Check logs (CSI Driver, AWS Provider, Pod)
2. Verify IAM permissions
3. Verify secret exists in AWS Secrets Manager
4. Review SecretProviderClass configuration
5. Contact platform team if unresolved

---

**Document Version**: 1.0
**Last Updated**: 2025-12-02
**Owner**: DevOps Team
