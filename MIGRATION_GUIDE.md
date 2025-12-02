# Migration Guide: Vault to AWS Secrets Manager

This guide provides step-by-step instructions for migrating from self-hosted HashiCorp Vault to AWS Secrets Manager with the Kubernetes Secrets Store CSI Driver.

## Executive Summary

**Goal**: Eliminate operational overhead of managing Vault infrastructure while maintaining secure secrets management.

**Changes**:
- **Remove**: HashiCorp Vault + External Secrets Operator
- **Add**: AWS Secrets Manager + Secrets Store CSI Driver

**Benefits**:
- Zero infrastructure management (no Vault pods, DynamoDB, S3)
- Lower operational costs
- AWS-managed security and high availability
- Simpler architecture

---

## Prerequisites

Before starting the migration:

- [ ] AWS Account with Secrets Manager permissions
- [ ] EKS cluster with OIDC provider configured
- [ ] Terraform installed (for IAM setup)
- [ ] AWS CLI configured
- [ ] Access to current Vault instance (for secret export)
- [ ] kubectl and helm CLI tools

---

## Migration Timeline

| Phase | Duration | Risk | Can Rollback |
|-------|----------|------|--------------|
| 1. Setup Infrastructure | 1-2 hours | Low | Yes |
| 2. Export & Migrate Secrets | 2-4 hours | Low | Yes |
| 3. Deploy CSI Driver | 30 minutes | Low | Yes |
| 4. Update Applications (Dev) | 1-2 hours | Medium | Yes |
| 5. Validate & Test | 2-4 hours | Low | Yes |
| 6. Production Rollout | 2-4 hours | Medium | Yes (with downtime) |
| 7. Cleanup | 1 hour | Low | N/A |

**Total Estimated Time**: 10-18 hours (can be spread over multiple days)

---

## Phase 1: Setup AWS Infrastructure (No Impact)

### 1.1 Deploy IAM Roles with Terraform

```bash
cd terraform

# Create main.tf if it doesn't exist
cat > main.tf <<'EOF'
provider "aws" {
  region = "us-east-1"  # UPDATE THIS
}

# Get EKS cluster data
data "aws_eks_cluster" "main" {
  name = "gitops-eks-cluster"  # UPDATE THIS
}

# Create IRSA role for CSI Driver
module "secrets_manager_irsa" {
  source = "./modules/secrets-manager-irsa"

  cluster_name      = "gitops-eks-cluster"  # UPDATE THIS
  oidc_provider_url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
  namespace         = "kube-system"
  service_account_name = "secrets-store-csi-driver"
  secret_prefix     = "*"  # Allow access to all secrets

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "gitops-platform"
  }
}

output "csi_driver_role_arn" {
  value = module.secrets_manager_irsa.role_arn
}
EOF

# Initialize and apply
terraform init
terraform plan
terraform apply

# Save the IAM role ARN
export CSI_DRIVER_ROLE_ARN=$(terraform output -raw csi_driver_role_arn)
echo "CSI Driver IAM Role ARN: $CSI_DRIVER_ROLE_ARN"
```

### 1.2 Update Infrastructure Manifests

```bash
# Update the CSI Driver kustomization with the actual IAM role ARN
sed -i "s|arn:aws:iam::ACCOUNT_ID:role/gitops-eks-cluster-secrets-csi-driver|${CSI_DRIVER_ROLE_ARN}|g" \
  infrastructure/secrets-store-csi/kustomization.yaml

# Commit the changes
git add infrastructure/secrets-store-csi/
git commit -m "feat: add secrets-store-csi infrastructure with IAM role"
git push
```

**Validation**:
```bash
# Verify IAM role exists
aws iam get-role --role-name gitops-eks-cluster-secrets-csi-driver

# Verify IAM policy
aws iam list-attached-role-policies --role-name gitops-eks-cluster-secrets-csi-driver
```

---

## Phase 2: Export and Migrate Secrets

### 2.1 Export Secrets from Vault

```bash
# Port forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR='http://localhost:8200'

# Login to Vault
vault login <your-vault-token>

# Create export directory
mkdir -p vault-export

# Export secrets (customize paths for your environment)
for env in production staging development; do
  echo "Exporting secrets for environment: $env"

  # List all secrets in the environment
  vault kv list -format=json secret/$env/ | jq -r '.[]' | while read app; do
    echo "  Exporting $env/$app"

    # Export each secret
    vault kv get -format=json secret/$env/$app > vault-export/${env}_${app}.json
  done
done

# Stop port forward
kill %1
```

### 2.2 Create Secrets in AWS Secrets Manager

```bash
cd vault-export

# Script to migrate secrets
for secret_file in *.json; do
  # Parse filename (e.g., production_myapp_database.json)
  env=$(echo $secret_file | cut -d_ -f1)
  app=$(echo $secret_file | cut -d_ -f2-)
  app=${app%.json}

  # Extract secret data
  secret_data=$(cat $secret_file | jq -r '.data.data')

  # Create secret in AWS Secrets Manager
  secret_name="${env}/${app}"
  echo "Creating secret: $secret_name"

  aws secretsmanager create-secret \
    --name "$secret_name" \
    --description "Migrated from Vault: ${env}/${app}" \
    --secret-string "$secret_data" \
    --region us-east-1 \
    --tags Key=Source,Value=Vault Key=Environment,Value=$env \
    2>/dev/null || \
  aws secretsmanager update-secret \
    --secret-id "$secret_name" \
    --secret-string "$secret_data" \
    --region us-east-1
done

cd ..
```

**Validation**:
```bash
# List all migrated secrets
aws secretsmanager list-secrets --region us-east-1

# Verify a specific secret
aws secretsmanager get-secret-value \
  --secret-id production/myapp/database \
  --region us-east-1
```

**IMPORTANT**: Store the vault-export directory securely and delete after successful migration!

---

## Phase 3: Deploy CSI Driver

### 3.1 Deploy via ArgoCD

```bash
# Apply the updated infrastructure-apps.yaml
git add applications/infrastructure-apps.yaml
git commit -m "feat: replace Vault/ESO with Secrets Store CSI Driver"
git push

# Sync the new application
argocd app sync secrets-store-csi

# Wait for deployment
argocd app wait secrets-store-csi --health --timeout 300
```

### 3.2 Verify CSI Driver Installation

```bash
# Check CSI Driver pods
kubectl get pods -n kube-system | grep csi

# Expected output:
# csi-secrets-store-provider-aws-xxxxx     1/1     Running
# csi-secrets-store-secrets-store-csi-driver-xxxxx  3/3  Running

# Check daemonset
kubectl get daemonset -n kube-system | grep secrets-store

# Check driver is registered
kubectl get csidriver
# Should see: secrets-store.csi.k8s.io

# Check logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws
```

---

## Phase 4: Update Applications (Start with Dev)

### 4.1 Update Helm Chart Values

```bash
# Update development environment values
vim charts/my-microservice/ci/dev-values.yaml

# Update the secretsManager section:
secretsManager:
  enabled: true
  region: us-east-1
  mountPath: /mnt/secrets
  objects:
    - objectName: "development/myapp/database"
      objectType: "secretsmanager"
      jmesPath:
        - path: url
          objectAlias: database-url
        - path: username
          objectAlias: database-username
        - path: password
          objectAlias: database-password
  syncToKubernetesSecret: true
  secretData:
    - objectName: database-url
      key: DATABASE_URL
    - objectName: database-username
      key: DATABASE_USERNAME
    - objectName: database-password
      key: DATABASE_PASSWORD

# Update serviceAccount with IAM role
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/gitops-eks-cluster-secrets-csi-driver"

# Commit changes
git add charts/my-microservice/ci/dev-values.yaml
git commit -m "feat(dev): migrate to AWS Secrets Manager"
git push
```

### 4.2 Deploy to Development

```bash
# Sync the application
argocd app sync my-microservice-dev

# Watch the deployment
kubectl get pods -n development -w

# Check if SecretProviderClass is created
kubectl get secretproviderclass -n development

# Check if secrets are mounted
kubectl exec -n development <pod-name> -- ls -la /mnt/secrets

# Check if Kubernetes Secret is synced
kubectl get secret my-microservice-secrets -n development
kubectl describe secret my-microservice-secrets -n development
```

### 4.3 Validate Application Functionality

```bash
# Check application logs
kubectl logs -n development -l app=my-microservice

# Test application endpoints
kubectl port-forward -n development svc/my-microservice 8080:80
curl http://localhost:8080/health

# Verify database connectivity
kubectl exec -n development <pod-name> -- env | grep DATABASE
```

---

## Phase 5: Rollout to Staging and Production

### 5.1 Update Staging

```bash
# Update staging values
vim charts/my-microservice/ci/staging-values.yaml
# (Same changes as dev, but with staging/ secret paths)

git add charts/my-microservice/ci/staging-values.yaml
git commit -m "feat(staging): migrate to AWS Secrets Manager"
git push

# Deploy
argocd app sync my-microservice-staging
argocd app wait my-microservice-staging --health --timeout 300

# Validate
kubectl get pods -n staging
kubectl exec -n staging <pod-name> -- ls -la /mnt/secrets
```

### 5.2 Update Production (with Monitoring)

**IMPORTANT**: Plan a maintenance window or use blue-green deployment.

```bash
# Update production values
vim charts/my-microservice/ci/production-values.yaml

secretsManager:
  enabled: true
  region: us-east-1
  mountPath: /mnt/secrets
  objects:
    - objectName: "production/myapp/database"
      objectType: "secretsmanager"
      jmesPath:
        - path: url
          objectAlias: database-url
        - path: username
          objectAlias: database-username
        - path: password
          objectAlias: database-password
    - objectName: "production/myapp/api-key"
      objectType: "secretsmanager"
      objectAlias: api-key
  syncToKubernetesSecret: true
  secretData:
    - objectName: database-url
      key: DATABASE_URL
    - objectName: database-username
      key: DATABASE_USERNAME
    - objectName: database-password
      key: DATABASE_PASSWORD
    - objectName: api-key
      key: API_KEY

# Commit
git add charts/my-microservice/ci/production-values.yaml
git commit -m "feat(production): migrate to AWS Secrets Manager"
git push

# Monitor deployment closely
argocd app sync my-microservice-production
kubectl get pods -n production -w

# Check each pod
for pod in $(kubectl get pods -n production -l app=my-microservice -o name); do
  echo "Checking $pod"
  kubectl exec -n production $pod -- ls -la /mnt/secrets
  kubectl logs -n production $pod --tail=50
done

# Verify service health
kubectl get svc -n production
curl https://myapp.example.com/health
```

---

## Phase 6: Cleanup (After Successful Migration)

### 6.1 Remove Vault and External Secrets Applications

```bash
# Delete ArgoCD applications
argocd app delete vault --yes
argocd app delete external-secrets --yes

# Verify deletion
kubectl get application -n argocd

# Remove from Git (already done in infrastructure-apps.yaml)
git pull
```

### 6.2 Cleanup AWS Resources

**WARNING**: Only do this after confirming Vault is no longer needed!

```bash
# List Vault resources
aws dynamodb list-tables | grep vault
aws s3 ls | grep vault
aws kms list-keys

# Delete Vault DynamoDB table (BACKUP FIRST!)
aws dynamodb create-backup --table-name vault-data --backup-name vault-data-final-backup
aws dynamodb delete-table --table-name vault-data

# Delete Vault S3 bucket (BACKUP FIRST!)
aws s3 sync s3://vault-snapshots s3://vault-snapshots-archive
aws s3 rb s3://vault-snapshots --force

# Optionally disable (not delete) KMS key
aws kms disable-key --key-id <vault-kms-key-id>
```

### 6.3 Remove Vault from Infrastructure Code

```bash
# Already removed in previous steps, verify:
ls -la infrastructure/

# Should NOT see vault/ or external-secrets/
# Should see secrets-store-csi/
```

### 6.4 Update Documentation

The documentation has already been updated in CLAUDE.md. Verify and update any additional docs:

```bash
# Check all references to Vault
grep -r "Vault" . --include="*.md"
grep -r "ExternalSecret" . --include="*.md"

# Update README.md, DEPLOYMENT_CHECKLIST.md, QUICK_REFERENCE.md as needed
```

---

## Rollback Procedures

### If Issues Found in Phase 3 (CSI Driver Deployment)

```bash
# Delete the CSI Driver application
argocd app delete secrets-store-csi --yes

# Restore Vault and External Secrets
git revert <commit-hash>
git push

argocd app sync vault
argocd app sync external-secrets
```

### If Issues Found in Phase 4/5 (Application Deployment)

```bash
# Rollback application to previous version
argocd app rollback my-microservice-production <previous-revision>

# Or revert Git commits
git revert <commit-hash>
git push
```

### Complete Rollback to Vault

```bash
# 1. Re-enable Vault and External Secrets in infrastructure-apps.yaml
git revert <migration-commit>
git push

# 2. Restore Vault data from backup
aws dynamodb restore-table-from-backup \
  --target-table-name vault-data \
  --backup-arn <backup-arn>

# 3. Sync infrastructure
argocd app sync vault
argocd app sync external-secrets

# 4. Rollback applications
argocd app rollback my-microservice-production
argocd app rollback my-microservice-staging
argocd app rollback my-microservice-dev
```

---

## Validation Checklist

After migration, verify:

- [ ] All pods in all environments are Running
- [ ] Secrets are mounted in pods at `/mnt/secrets`
- [ ] Kubernetes Secrets are created and populated
- [ ] Applications can connect to databases
- [ ] Application health checks pass
- [ ] No errors in pod logs related to secrets
- [ ] CSI Driver pods are healthy
- [ ] SecretProviderClass resources exist in each namespace
- [ ] Reloader is triggering updates when secrets change
- [ ] Monitoring and alerting are functional

---

## Testing Secret Rotation

```bash
# Update a secret in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '{"url":"postgresql://prod-db:5432/myapp","username":"app_user","password":"NEW_PASSWORD"}' \
  --region us-east-1

# Wait for CSI Driver to sync (default: 2 minutes)
sleep 120

# Check if secret is updated in pod
kubectl exec -n production <pod-name> -- cat /mnt/secrets/database-password

# Check if Kubernetes Secret is updated
kubectl get secret my-microservice-secrets -n production -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d

# Reloader should trigger rolling update within a few minutes
kubectl get pods -n production -w
```

---

## Troubleshooting

### Secrets Not Mounting

```bash
# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=100

# Check AWS provider logs
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws --tail=100

# Check pod events
kubectl describe pod <pod-name> -n <namespace> | grep -A 20 Events

# Verify IRSA is working
kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=my-microservice -n production -- \
  sts get-caller-identity

# Check SecretProviderClass
kubectl describe secretproviderclass <name> -n <namespace>
```

### IAM Permission Issues

```bash
# Verify IAM role trust policy
aws iam get-role --role-name gitops-eks-cluster-secrets-csi-driver

# Verify IAM policy permissions
aws iam get-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/gitops-eks-cluster-secrets-manager-read \
  --version-id v1

# Test from pod
kubectl run aws-test --rm -it --image=amazon/aws-cli \
  --serviceaccount=my-microservice -n production -- \
  secretsmanager get-secret-value --secret-id production/myapp/database --region us-east-1
```

### Secret Not Found in AWS

```bash
# List all secrets
aws secretsmanager list-secrets --region us-east-1

# Check specific secret
aws secretsmanager describe-secret --secret-id production/myapp/database --region us-east-1

# Verify secret value
aws secretsmanager get-secret-value --secret-id production/myapp/database --region us-east-1
```

---

## Cost Comparison

### Before (Vault on EKS)
- **EKS nodes**: 3 x t3.medium for Vault = ~$90/month
- **DynamoDB**: $5-10/month
- **S3**: $1-2/month
- **KMS**: $1/month
- **EBS volumes**: $10/month
- **Total**: ~$107-113/month

### After (AWS Secrets Manager)
- **Secrets Manager**: $0.40 per secret/month + $0.05 per 10,000 API calls
- **Estimated for 50 secrets**: ~$20-30/month
- **Savings**: ~$80-90/month (70-80% reduction)

---

## Support and Resources

- **AWS Secrets Manager**: https://docs.aws.amazon.com/secretsmanager/
- **Secrets Store CSI Driver**: https://secrets-store-csi-driver.sigs.k8s.io/
- **AWS Provider**: https://github.com/aws/secrets-store-csi-driver-provider-aws

---

**Migration Date**: _______________
**Performed By**: _______________
**Sign-off**: _______________
