# GitOps Kubernetes Platform on AWS EKS

A production-ready, GitOps-based Kubernetes platform running on Amazon EKS with complete CI/CD automation, secrets management via AWS Secrets Manager, service mesh, and observability.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Guide](#deployment-guide)
- [CI/CD Pipeline](#cicd-pipeline)
- [Secrets Management](#secrets-management)
- [Networking & Ingress](#networking--ingress)
- [Service Mesh](#service-mesh)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Architecture Overview

This platform implements a complete GitOps workflow where:

1. **Git is the single source of truth** for all cluster configuration and application state
2. **CI builds and packages** applications into OCI artifacts (Helm charts + Docker images)
3. **CD (ArgoCD) deploys** from Git declarations, pulling artifacts from registries
4. **AWS Secrets Manager provides secrets** via Kubernetes Secrets Store CSI Driver
5. **Service Mesh (Linkerd)** enables mTLS for all service-to-service communication
6. **Reloader watches** ConfigMaps/Secrets and triggers rolling updates automatically

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   Git Repository  │
                    │  (Source of Truth)│
                    └──────────────────┘
                              │
                ┌─────────────┴─────────────┐
                ▼                           ▼
        ┌───────────────┐          ┌──────────────┐
        │  CI Pipeline  │          │   ArgoCD     │
        │ (GitHub       │          │ (GitOps      │
        │  Actions)     │          │  Operator)   │
        └───────────────┘          └──────────────┘
                │                           │
                ▼                           ▼
        ┌───────────────┐          ┌──────────────┐
        │  ECR/OCI      │────────▶ │  EKS Cluster │
        │  Registry     │          │              │
        └───────────────┘          └──────────────┘
                                            │
                    ┌───────────────────────┼───────────────────────┐
                    ▼                       ▼                       ▼
            ┌──────────────┐      ┌──────────────┐       ┌──────────────┐
            │   Traefik    │      │   Linkerd    │       │AWS Secrets   │
            │   Ingress    │      │Service Mesh  │       │  Manager +   │
            │              │      │              │       │  CSI Driver  │
            └──────────────┘      └──────────────┘       └──────────────┘
```

---

## Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| **Orchestration** | Amazon EKS | 1.28+ | Managed Kubernetes control plane |
| **GitOps** | ArgoCD | 9.0.6 | Continuous deployment operator |
| **Package Manager** | Helm | 3.14+ | Application packaging |
| **Configuration** | Kustomize | 5.0+ | Environment-specific overlays |
| **Secrets** | AWS Secrets Manager | - | Fully managed secrets service |
| **Secret Sync** | Secrets Store CSI Driver | 1.4.1 | Mount secrets as volumes |
| **AWS Provider** | AWS Provider for CSI Driver | 0.3.7 | AWS Secrets Manager integration |
| **Config Reload** | Reloader | 1.0.79 | Automatic pod updates on config changes |
| **Service Mesh** | Linkerd | 2.14+ | mTLS, traffic management |
| **Ingress** | Traefik v3 | 26.0+ | API Gateway and ingress controller |
| **CI** | GitHub Actions | - | Build, test, package automation |

---

## Prerequisites

### Required Tools

```bash
# Install required CLI tools
brew install kubectl helm aws-cli argocd terraform jq yq
```

### AWS Resources

Before deploying, you need:

1. **EKS Cluster** (1.28+) with OIDC provider enabled
2. **ECR Repository** for Docker images and Helm charts
3. **IAM Roles** for service accounts (IRSA) with Secrets Manager permissions

**Deploy AWS resources using Terraform:**

```bash
cd terraform
terraform init
terraform plan
terraform apply

# Capture the CSI Driver IAM role ARN
export CSI_DRIVER_ROLE_ARN=$(terraform output -raw csi_driver_role_arn)
```

---

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/YOUR_ORG/gitops-platform.git
cd gitops-platform

# Update repository URLs
find . -type f -name "*.yaml" -exec sed -i '' \
  's|YOUR_ORG/gitops-platform|your-org/gitops-platform|g' {} +

# Update ECR registry
find . -type f -name "*.yaml" -exec sed -i '' \
  's|YOUR_ECR_REGISTRY|123456789012.dkr.ecr.us-east-1.amazonaws.com|g' {} +

# Update domain names
find . -type f -name "*.yaml" -exec sed -i '' \
  's|example.com|yourdomain.com|g' {} +

# Update IAM role ARNs
sed -i "s|arn:aws:iam::ACCOUNT_ID:role/[^\"]*|${CSI_DRIVER_ROLE_ARN}|g" \
  infrastructure/secrets-store-csi/kustomization.yaml
```

### 2. Connect to EKS Cluster

```bash
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1
kubectl cluster-info
```

### 3. Bootstrap the Platform

```bash
cd bootstrap
./install.sh
```

This script will:

- Install ArgoCD via Helm
- Deploy the root App of Apps
- Configure GitOps automation

**Expected output:**

```
ArgoCD URL: https://a123456789.us-east-1.elb.amazonaws.com
Username: admin
Password: <random-password>
```

### 4. Access ArgoCD UI

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward if not using LoadBalancer
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser
open https://localhost:8080
```

### 5. Verify Deployment

```bash
# Check all ArgoCD applications
kubectl get application -n argocd

# Check infrastructure pods
kubectl get pods -n kube-system | grep csi
kubectl get pods -n traefik
kubectl get pods -n linkerd
kubectl get pods -n reloader

# Verify all apps are healthy
argocd app list
```

---

## Deployment Guide

### Pre-Deployment Checklist

- [ ] EKS cluster created (v1.28+) with OIDC provider enabled
- [ ] ECR repository created for Docker images
- [ ] ECR repository created for Helm charts (OCI format)
- [ ] IAM role created for CSI Driver with IRSA
- [ ] VPC and subnets configured
- [ ] Security groups configured
- [ ] EKS node groups created
- [ ] `kubectl`, `helm`, `aws-cli`, `argocd` CLI tools installed
- [ ] Repository cloned and configured (URLs, domains, IAM ARNs updated)
- [ ] GitHub Actions secrets configured (AWS credentials, ArgoCD credentials)

### Phase 1: Deploy Infrastructure via Terraform

**Duration:** 30 minutes | **Risk:** Low | **Rollback:** Yes

```bash
cd terraform

# Review and update terraform configuration
# Ensure cluster_name, region, and other variables are correct

terraform init
terraform plan
terraform apply -auto-approve

# Capture outputs
export CSI_DRIVER_ROLE_ARN=$(terraform output -raw csi_driver_role_arn)
echo "CSI Driver IAM Role ARN: $CSI_DRIVER_ROLE_ARN"
```

**Validation:**
```bash
# Verify IAM role exists
aws iam get-role --role-name gitops-eks-cluster-secrets-csi-driver

# Verify IAM policy attached
aws iam list-attached-role-policies --role-name gitops-eks-cluster-secrets-csi-driver
```

### Phase 2: Bootstrap ArgoCD

**Duration:** 15 minutes | **Risk:** Low | **Rollback:** Yes

```bash
# Connect to EKS cluster
aws eks update-kubeconfig --name gitops-eks-cluster --region us-east-1
kubectl cluster-info

# Execute bootstrap script
./bootstrap/install.sh

# Verify ArgoCD installation
kubectl get pods -n argocd
kubectl get application -n argocd

# Retrieve admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Phase 3: Deploy Infrastructure Components

**Duration:** 30 minutes | **Risk:** Low | **Rollback:** Yes

Infrastructure components are deployed automatically via the App of Apps pattern:

```bash
# Verify infrastructure apps are synced
kubectl get application -n argocd | grep infrastructure

# Expected output:
# secrets-store-csi       Synced  Healthy
# traefik                 Synced  Healthy
# linkerd                 Synced  Healthy
# reloader                Synced  Healthy
# argocd-self-managed     Synced  Healthy

# Check CSI Driver deployment
kubectl get pods -n kube-system | grep csi
kubectl get daemonset -n kube-system | grep secrets-store
kubectl get csidriver secrets-store.csi.k8s.io

# Check Traefik
kubectl get pods -n traefik
kubectl get svc -n traefik

# Check Linkerd
kubectl get pods -n linkerd
linkerd check

# Check Reloader
kubectl get pods -n reloader
```

### Phase 4: Configure Linkerd Certificates

**Duration:** 15 minutes | **Risk:** Low | **Rollback:** Yes

```bash
cd infrastructure/linkerd
./generate-certs.sh

# Apply certificates to cluster
kubectl create namespace linkerd
kubectl create secret tls linkerd-trust-anchor \
  --cert=certs/ca.crt \
  --key=certs/ca.key \
  --namespace=linkerd

kubectl create secret tls linkerd-identity-issuer \
  --cert=certs/issuer.crt \
  --key=certs/issuer.key \
  --namespace=linkerd

# Backup certificates securely
cp -r certs /secure/backup/location/

# Restart Linkerd to use new certificates
kubectl rollout restart deployment -n linkerd
```

### Phase 5: Create Secrets in AWS Secrets Manager

**Duration:** 30-60 minutes | **Risk:** Low | **Rollback:** Yes

```bash
# Create production secrets
aws secretsmanager create-secret \
  --name production/myapp/database \
  --description "Production database credentials" \
  --secret-string '{"url":"postgresql://prod-db.example.com:5432/myapp","username":"app_user","password":"CHANGE_ME_SECURE_PASSWORD"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=production Key=Application,Value=myapp

# Create API key secret
aws secretsmanager create-secret \
  --name production/myapp/api-key \
  --description "Production API key" \
  --secret-string "prod-api-key-CHANGE_ME" \
  --region us-east-1 \
  --tags Key=Environment,Value=production Key=Application,Value=myapp

# Staging secrets
aws secretsmanager create-secret \
  --name staging/myapp/database \
  --description "Staging database credentials" \
  --secret-string '{"url":"postgresql://staging-db.example.com:5432/myapp","username":"app_user","password":"CHANGE_ME"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=staging Key=Application,Value=myapp

# Development secrets
aws secretsmanager create-secret \
  --name development/myapp/database \
  --description "Development database credentials" \
  --secret-string '{"url":"postgresql://dev-db.example.com:5432/myapp","username":"app_user","password":"CHANGE_ME"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=development Key=Application,Value=myapp

# List all created secrets
aws secretsmanager list-secrets --region us-east-1 --output table
```

**Validation:**
```bash
# Verify secrets exist
aws secretsmanager get-secret-value \
  --secret-id production/myapp/database \
  --region us-east-1
```

### Phase 6: Deploy Applications

**Duration:** 1-2 hours | **Risk:** Medium | **Rollback:** Yes

#### 6.1 Deploy to Development Environment

```bash
# Deploy development App of Apps
kubectl apply -f applications/app-of-apps-dev.yaml

# Sync application
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

#### 6.2 Deploy to Staging Environment

```bash
# Deploy staging App of Apps
kubectl apply -f applications/app-of-apps-staging.yaml

# Sync application
argocd app sync my-microservice-staging
argocd app wait my-microservice-staging --health --timeout 300

# Validation (same as development)
kubectl get pods -n staging
kubectl get secretproviderclass -n staging
kubectl exec -n staging <pod> -- ls -la /mnt/secrets
kubectl get secret my-microservice-secrets -n staging
```

#### 6.3 Deploy to Production Environment

**IMPORTANT:** Requires production readiness validation and change management approval.

**Pre-deployment checklist:**
- [ ] Dev and Staging deployments successful
- [ ] All tests passing
- [ ] Monitoring and alerting configured
- [ ] Rollback plan documented
- [ ] Team notified of deployment
- [ ] Maintenance window scheduled (if needed)

```bash
# Deploy production App of Apps
kubectl apply -f applications/app-of-apps-production.yaml

# Sync application
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

### Phase 7: Verify Platform Health

```bash
# All ArgoCD applications should be Synced and Healthy
kubectl get application -n argocd

# All infrastructure pods running
kubectl get pods -n kube-system | grep csi
kubectl get pods -n traefik
kubectl get pods -n linkerd
kubectl get pods -n reloader

# All application pods running
kubectl get pods -n production
kubectl get pods -n staging
kubectl get pods -n development

# Check ingress LoadBalancer
kubectl get svc -n traefik

# Dashboards accessible:
# - ArgoCD: https://argocd.example.com
# - Traefik: https://traefik.example.com
# - Linkerd: https://linkerd.example.com

# Service mesh mTLS enabled
linkerd check
linkerd viz stat deployment -n production
```

---

## CI/CD Pipeline

### CI: Build and Package

The CI pipeline (`.github/workflows/ci-build-deploy.yaml`) performs:

1. **Lint** Helm charts with all environment values
2. **Validate** manifests with kubeval
3. **Build** Docker image
4. **Push** to ECR
5. **Package** Helm chart
6. **Push** Helm chart to OCI registry (ECR)
7. **Update** Git with new image tag
8. **Trigger** ArgoCD sync (automatic via Git polling)

### CD: ArgoCD Automatic Deployment

ArgoCD continuously:

1. **Watches** Git repository for changes (polling interval: 3 minutes)
2. **Compares** desired state (Git) vs actual state (cluster)
3. **Syncs** differences automatically (if auto-sync enabled)
4. **Mounts** secrets from AWS Secrets Manager via CSI Driver
5. **Triggers** Reloader for rolling updates on config changes

### Triggering a Deployment

```bash
# Push code to trigger CI
git add .
git commit -m "feat: new feature"
git push origin main

# CI pipeline will:
# 1. Build image: 123456789.dkr.ecr.us-east-1.amazonaws.com/my-microservice:v1.2.3
# 2. Package Helm chart
# 3. Update charts/my-microservice/ci/production-values.yaml with new tag
# 4. Commit and push

# ArgoCD will automatically detect the Git change and deploy
# Expected time: ~5 minutes from commit to running in production
```

---

## Secrets Management

### Using AWS Secrets Manager with CSI Driver

**Architecture Flow:**

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
Pod with CSI Volume
  ├── /mnt/secrets/db-url      ← Mounted as files
  ├── /mnt/secrets/db-pass
  └── env: DATABASE_URL        ← From synced K8s Secret
       ↓
Reloader watches Secret changes
       ↓
Triggers rolling update
```

### Creating Secrets

**1. Create Secret in AWS Secrets Manager:**

```bash
aws secretsmanager create-secret \
  --name production/myapp/db \
  --description "Database credentials for myapp production" \
  --secret-string '{"host":"db.example.com","username":"dbuser","password":"secretpass"}' \
  --region us-east-1 \
  --tags Key=Environment,Value=production Key=Application,Value=myapp
```

**2. Configure SecretProviderClass (already in Helm chart template):**

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: my-microservice-secrets
  namespace: production
spec:
  provider: aws
  parameters:
    region: us-east-1
    objects: |
      - objectName: "production/myapp/database"
        objectType: "secretsmanager"
        jmesPath:
          - path: url
            objectAlias: database-url
          - path: username
            objectAlias: database-username
          - path: password
            objectAlias: database-password
  secretObjects:
    - secretName: my-microservice-secrets
      type: Opaque
      data:
        - objectName: database-url
          key: DATABASE_URL
        - objectName: database-username
          key: DATABASE_USERNAME
        - objectName: database-password
          key: DATABASE_PASSWORD
```

**3. Mount in Deployment (already configured in Helm chart template):**

```yaml
spec:
  serviceAccountName: my-microservice  # Must have IRSA annotation
  containers:
    - name: app
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: my-microservice-secrets
              key: DATABASE_URL
      volumeMounts:
        - name: secrets-store
          mountPath: /mnt/secrets
          readOnly: true
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: my-microservice-secrets
```

### Updating Secrets

```bash
# Update secret in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '{"url":"postgresql://prod-db:5432/myapp","username":"app_user","password":"NEW_PASSWORD"}' \
  --region us-east-1

# CSI Driver syncs automatically (default: 2-minute poll interval)
# Reloader triggers rolling update automatically when K8s Secret changes
# No manual intervention needed!
```

### Testing Secret Rotation

```bash
# Update a secret
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '{"url":"...","password":"NEW_PASSWORD"}' \
  --region us-east-1

# Wait for CSI Driver to sync (2 minutes)
sleep 120

# Verify file updated in pod
kubectl exec -n production <pod> -- cat /mnt/secrets/database-password

# Verify Kubernetes Secret updated
kubectl get secret my-microservice-secrets -n production \
  -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d

# Reloader should trigger rolling update
kubectl get events -n production --sort-by='.lastTimestamp' | grep Reloader
kubectl get pods -n production -w
```

---

## Networking & Ingress

### Traefik IngressRoute

All ingress uses Traefik's `IngressRoute` CRD for advanced features:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: production
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.example.com`)
      kind: Rule
      services:
        - name: my-app
          port: 80
      middlewares:
        - name: rate-limit
        - name: default-headers
  tls:
    secretName: myapp-tls
```

### Accessing Dashboards

```bash
# Traefik Dashboard
# URL: https://traefik.example.com
# Credentials: admin / changeme (update in production!)

# ArgoCD
# URL: https://argocd.example.com

# Linkerd Viz
# URL: https://linkerd.example.com
```

---

## Service Mesh

### Linkerd mTLS

All services in namespaces with `linkerd.io/inject: enabled` annotation automatically get:

- **Mutual TLS** for service-to-service communication
- **Automatic retries** and timeouts
- **Traffic metrics** and observability
- **Circuit breaking** and load balancing

### Enable Linkerd for a Namespace

```bash
kubectl annotate namespace production linkerd.io/inject=enabled
```

### Check mTLS Status

```bash
# Check Linkerd health
linkerd check

# View deployment statistics
linkerd viz stat deployment -n production

# Tap traffic (live view)
linkerd viz tap deployment/my-app -n production

# Check proxy injection
kubectl get pod <pod> -n production -o yaml | grep linkerd-proxy
```

---

## Monitoring & Observability

### Service Monitors

Applications expose Prometheus metrics automatically:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    path: /metrics
```

### Key Metrics Endpoints

- **Traefik:** `:9100/metrics`
- **ArgoCD:** `:8082/metrics`
- **Linkerd:** `:4191/metrics`
- **Applications:** `:8080/metrics` (configured per app)

---

## Troubleshooting

### ArgoCD App Not Syncing

```bash
# Check app status
argocd app get my-microservice-production

# Check sync errors
kubectl describe application my-microservice-production -n argocd

# Force sync
argocd app sync my-microservice-production --prune

# Refresh and hard refresh
argocd app refresh my-microservice-production
argocd app refresh my-microservice-production --hard
```

### Secrets Not Mounting (CSI Driver Issues)

```bash
# Check CSI Driver pods
kubectl get pods -n kube-system | grep csi
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Check AWS Provider logs
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws

# Check SecretProviderClass
kubectl get secretproviderclass -n production
kubectl describe secretproviderclass my-microservice-secrets -n production

# Check if secret exists in AWS
aws secretsmanager get-secret-value \
  --secret-id production/myapp/database \
  --region us-east-1

# Verify IRSA permissions
kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=my-microservice -n production -- \
  sts get-caller-identity

kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=my-microservice -n production -- \
  secretsmanager get-secret-value --secret-id production/myapp/database --region us-east-1

# Check pod events
kubectl describe pod <pod-name> -n production | grep -A 20 Events

# Verify CSI volume mounted
kubectl describe pod <pod-name> -n production | grep -A 10 "Volumes:"
```

### Pods Not Reloading on Config Changes

```bash
# Check Reloader is running
kubectl get pods -n reloader

# Verify annotations on deployment
kubectl get deployment my-app -n production -o yaml | grep reloader

# Required annotation:
# reloader.stakater.com/auto: "true"

# Check Reloader logs
kubectl logs -l app=reloader -n reloader
```

### Linkerd Issues

```bash
# Check Linkerd health
linkerd check

# Check proxy injection
kubectl get pod my-app-xxx -o yaml | grep linkerd

# View proxy logs
kubectl logs my-app-xxx -c linkerd-proxy -n production

# Check mTLS
linkerd viz stat deployment -n production
linkerd viz edges deployment -n production
```

---

## Best Practices

### 1. Never `kubectl apply` Manually

Always commit changes to Git and let ArgoCD sync:

```bash
# ❌ DON'T
kubectl apply -f deployment.yaml

# ✅ DO
git add deployment.yaml
git commit -m "update: increase replicas"
git push
```

### 2. Use Semantic Versioning

```bash
# Tag releases properly
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

### 3. Environment Promotion

```bash
# Test in dev first
git push origin develop

# After validation, promote to production
git checkout main
git merge develop
git push origin main
```

### 4. Backup Critical Data

```bash
# Backup ArgoCD applications
kubectl get application -n argocd -o yaml > argocd-backup.yaml

# Backup Linkerd certificates
cp -r infrastructure/linkerd/certs /secure/backup/location/

# Export AWS Secrets Manager secrets (for DR)
aws secretsmanager list-secrets --region us-east-1 > secrets-inventory.json
```

### 5. Rotate Secrets Regularly

```bash
# Update secret in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/db \
  --secret-string '{"password":"new-secure-password"}' \
  --region us-east-1

# CSI Driver will sync within rotationPollInterval (default: 2 minutes)
# Reloader will trigger rolling update automatically
```

### 6. Security Best Practices

- **Never commit secrets to Git** - Use AWS Secrets Manager
- **All service-to-service traffic uses mTLS** - Enabled via Linkerd
- **Read-only root filesystems** - Enforced in pod security contexts
- **Non-root containers** - All containers run as non-root users
- **RBAC enabled** - Service accounts with least-privilege IAM policies (IRSA)
- **Secrets encryption at rest** - AWS Secrets Manager with AWS KMS
- **Automatic secret rotation** - CSI Driver supports rotation polling
- **TLS everywhere** - Traefik handles TLS termination

---

## Success Criteria Validation

Verify the platform meets all success criteria:

### ✅ Automated Deployment (< 5 minutes)

```bash
# Start timer
time git push origin main

# Watch ArgoCD
argocd app wait my-microservice-production --timeout 300

# Expected: < 5 minutes from commit to running
```

### ✅ Secret Changes Trigger Rollouts

```bash
# Update secret in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/db \
  --secret-string '{"password":"new-pass"}' \
  --region us-east-1

# Watch pods restart (should happen within 2-5 minutes)
kubectl get pods -n production -w
```

### ✅ Traefik Dashboard Accessible

```bash
# Access dashboard
open https://traefik.example.com

# Should see:
# - All IngressRoutes
# - Active middlewares
# - Traffic statistics
```

### ✅ ArgoCD Shows All Apps Healthy

```bash
kubectl get application -n argocd

# All apps should show:
# STATUS: Synced, Healthy
```

### ✅ Service Mesh mTLS Enabled

```bash
linkerd check
linkerd viz stat deployment -n production

# Should show:
# - SUCCESS: encrypted (mTLS) traffic
```

---

## Deployment Checklist Summary

### Pre-Deployment
- [ ] AWS resources created (EKS, ECR, IAM roles)
- [ ] Repository configured (URLs, domains, IAM ARNs)
- [ ] GitHub Actions secrets configured
- [ ] Tools installed (kubectl, helm, aws-cli, argocd)

### Infrastructure Deployment
- [ ] Terraform applied (IAM roles for IRSA)
- [ ] ArgoCD bootstrapped
- [ ] CSI Driver deployed and healthy
- [ ] Traefik deployed and healthy
- [ ] Linkerd deployed and healthy
- [ ] Reloader deployed
- [ ] Linkerd certificates generated and applied

### Secrets Management
- [ ] Secrets created in AWS Secrets Manager
- [ ] SecretProviderClass configured in Helm charts
- [ ] ServiceAccounts have IRSA annotations
- [ ] CSI volumes configured in Deployments

### Application Deployment
- [ ] Development environment deployed and validated
- [ ] Staging environment deployed and validated
- [ ] Production environment deployed and validated
- [ ] All health checks passing
- [ ] Secret rotation tested
- [ ] Reloader triggering rolling updates

### Post-Deployment
- [ ] All ArgoCD apps show Synced/Healthy
- [ ] Monitoring and alerting configured
- [ ] Backups configured
- [ ] Documentation updated
- [ ] Team training completed

---

## Contributing

1. Create a feature branch
2. Make changes
3. Test in dev environment
4. Submit PR
5. After approval, merge to main

---

## License

MIT License - see LICENSE file

---

## Support

- **Documentation:** [docs/](./docs/)
- **Issues:** https://github.com/YOUR_ORG/gitops-platform/issues
- **Slack:** #gitops-platform

---

**Last Updated:** 2025-12-02
**Platform Version:** 2.0.0 (AWS Secrets Manager)
