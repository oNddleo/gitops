# VSF-Miniapp Configuration Guide

This guide shows you exactly what needs to be configured before deploying.

---

## ⚠️ Required Updates

### 1. AWS Configuration

**Location:** All `charts/vsf-miniapp/ci/*.yaml` files

**Find and replace:**
```bash
# Update ECR Registry
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i 's|YOUR_ECR_REGISTRY|123456789012.dkr.ecr.us-east-1.amazonaws.com|g' {} \;

# Update AWS Account ID
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i 's|ACCOUNT_ID|123456789012|g' {} \;
```

**Manual update needed:**
- Replace `123456789012` with your actual AWS Account ID
- Replace `us-east-1` with your AWS region if different

---

### 2. Domain Names

**Files to update:**
- `charts/vsf-miniapp/ci/service-a-dev.yaml`
- `charts/vsf-miniapp/ci/service-a-staging.yaml`
- `charts/vsf-miniapp/ci/service-a-production.yaml`
- `charts/vsf-miniapp/ci/service-b-*.yaml`

**Current placeholders:**
```yaml
# Development
ingress:
  hosts:
    - host: service-a-dev.vsf-miniapp.local  # UPDATE THIS

# Staging
ingress:
  hosts:
    - host: service-a-staging.vsf-miniapp.com  # UPDATE THIS

# Production
ingress:
  hosts:
    - host: service-a.vsf-miniapp.com  # UPDATE THIS
```

**Update to your domains:**
```bash
# Example: Update to your actual domain
sed -i 's/vsf-miniapp.com/your-domain.com/g' charts/vsf-miniapp/ci/*.yaml
```

---

### 3. AWS Secrets Manager Secrets

**Required secrets before deployment:**

#### Service A Secrets:

```bash
# Development
aws secretsmanager create-secret \
  --name dev/vsf-miniapp/service-a/database \
  --description "Service A dev database credentials" \
  --secret-string '{
    "url": "postgresql://dev-db.internal:5432/servicea",
    "username": "dev_user",
    "password": "CHANGE_ME"
  }' \
  --region us-east-1

# Staging
aws secretsmanager create-secret \
  --name staging/vsf-miniapp/service-a/database \
  --description "Service A staging database credentials" \
  --secret-string '{
    "url": "postgresql://staging-db.internal:5432/servicea",
    "username": "staging_user",
    "password": "CHANGE_ME"
  }' \
  --region us-east-1

# Production - Database
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-a/database \
  --description "Service A production database credentials" \
  --secret-string '{
    "url": "postgresql://prod-db.rds.amazonaws.com:5432/servicea",
    "username": "prod_user",
    "password": "STRONG_PASSWORD_HERE",
    "maxPoolSize": "20"
  }' \
  --region us-east-1

# Production - Kafka
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-a/kafka \
  --description "Service A production Kafka credentials" \
  --secret-string '{
    "brokers": "kafka-1.internal:9092,kafka-2.internal:9092",
    "username": "service_a_kafka",
    "password": "STRONG_PASSWORD_HERE"
  }' \
  --region us-east-1
```

#### Service B Secrets:

```bash
# Development
aws secretsmanager create-secret \
  --name dev/vsf-miniapp/service-b/mongodb \
  --description "Service B dev MongoDB credentials" \
  --secret-string '{
    "connectionString": "mongodb://dev-mongo:27017/serviceb",
    "database": "serviceb"
  }' \
  --region us-east-1

# Staging - MongoDB
aws secretsmanager create-secret \
  --name staging/vsf-miniapp/service-b/mongodb \
  --description "Service B staging MongoDB credentials" \
  --secret-string '{
    "connectionString": "mongodb://admin:password@staging-mongo:27017/serviceb?authSource=admin",
    "database": "serviceb"
  }' \
  --region us-east-1

# Staging - Redis
aws secretsmanager create-secret \
  --name staging/vsf-miniapp/service-b/redis \
  --description "Service B staging Redis credentials" \
  --secret-string '{
    "host": "staging-redis.internal",
    "password": "CHANGE_ME"
  }' \
  --region us-east-1

# Production - MongoDB
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-b/mongodb \
  --description "Service B production MongoDB credentials" \
  --secret-string '{
    "connectionString": "mongodb://admin:STRONG_PASSWORD@prod-mongo:27017/serviceb?authSource=admin",
    "database": "serviceb"
  }' \
  --region us-east-1

# Production - Redis
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-b/redis \
  --description "Service B production Redis credentials" \
  --secret-string '{
    "host": "prod-redis.elasticache.amazonaws.com",
    "port": "6379",
    "password": "STRONG_PASSWORD_HERE"
  }' \
  --region us-east-1

# Production - JWT Secret
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-b/jwt \
  --description "Service B production JWT secret" \
  --secret-string '{
    "secret": "GENERATE_RANDOM_256BIT_SECRET_HERE"
  }' \
  --region us-east-1
```

---

### 4. IAM Roles for IRSA

**Required for each service per environment:**

Create IAM roles using Terraform or manually:

```hcl
# Terraform example
module "service_a_dev_irsa" {
  source = "./terraform/modules/secrets-manager-irsa"

  cluster_name    = "gitops-eks-cluster"
  namespace       = "dev"
  service_account = "service-a"
  secret_arns = [
    "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:dev/vsf-miniapp/service-a/*"
  ]
}

module "service_a_prod_irsa" {
  source = "./terraform/modules/secrets-manager-irsa"

  cluster_name    = "gitops-eks-cluster"
  namespace       = "production"
  service_account = "service-a"
  secret_arns = [
    "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:production/vsf-miniapp/service-a/*"
  ]
}

# Similar for service-b in all environments
```

**Or using AWS CLI:**

```bash
# Create IRSA role for service-a-dev
eksctl create iamserviceaccount \
  --name service-a \
  --namespace dev \
  --cluster gitops-eks-cluster \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/vsf-miniapp-service-a-dev-secrets-reader \
  --approve \
  --region us-east-1
```

---

## ✅ Verification Checklist

Before deploying, verify:

- [ ] ECR registry URL updated in all service values files
- [ ] AWS Account ID updated in all IRSA annotations
- [ ] Domain names updated to match your DNS
- [ ] AWS Secrets created in Secrets Manager
- [ ] IAM roles created with IRSA for each service
- [ ] EKS cluster has OIDC provider enabled
- [ ] Secrets Store CSI Driver installed in cluster
- [ ] Linkerd installed in cluster
- [ ] Traefik installed in cluster
- [ ] ArgoCD installed and accessible

---

## 📝 Quick Update Commands

### Update All Placeholders at Once

```bash
# Set your values
export ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"
export DOMAIN="your-domain.com"

# Update ECR registry
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|YOUR_ECR_REGISTRY|${ECR_REGISTRY}|g" {} \;

# Update AWS Account ID
find charts/vsf-miniapp/ci/ -name "*.yaml" -exec sed -i "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" {} \;

# Update domains
find charts/vsf-miniapp/ci/ -name "*-production.yaml" -exec sed -i "s|vsf-miniapp.com|${DOMAIN}|g" {} \;
find charts/vsf-miniapp/ci/ -name "*-staging.yaml" -exec sed -i "s|vsf-miniapp.com|staging.${DOMAIN}|g" {} \;
find charts/vsf-miniapp/ci/ -name "*-dev.yaml" -exec sed -i "s|vsf-miniapp.local|dev.${DOMAIN}|g" {} \;

# Verify changes
git diff charts/vsf-miniapp/ci/
```

---

## 🚀 Deployment Order

1. **Update configuration** (this file)
2. **Create AWS secrets** (see section 3)
3. **Create IAM roles** (see section 4)
4. **Commit and push** to GitHub
5. **Deploy infrastructure** (Linkerd, Traefik, CSI Driver)
6. **Deploy dev** environment first
7. **Verify dev** deployment
8. **Deploy staging**
9. **Deploy production**

---

## 📚 Reference

- **AWS Secrets Manager**: `us-east-1` region (change if needed)
- **GitHub Repository**: `https://github.com/oNddleo/gitops.git`
- **ArgoCD Server**: Update in `.github/workflows/` if different

---

## 🔧 Service-Specific Configuration

### Service A (Java Spring Boot)

**Port:** 8080
**Health endpoints:** `/actuator/health/liveness`, `/actuator/health/readiness`
**Metrics:** `/actuator/prometheus` on port 8081
**Secrets needed:** Database, Kafka (production only)

### Service B (Node.js Express)

**Port:** 3000
**Health endpoints:** `/health/live`, `/health/ready`
**Metrics:** `/metrics` on port 3000
**Secrets needed:** MongoDB, Redis (staging/prod), JWT (prod only)

---

## ❓ Need Help?

Check these docs:
- [MULTI_SERVICE_SUMMARY.md](MULTI_SERVICE_SUMMARY.md) - Quick reference
- [ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md) - Detailed architecture
- [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) - Step-by-step guide
