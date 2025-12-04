# VSF-Miniapp Multi-Service Implementation Guide

This guide provides step-by-step instructions for transforming your current single-service `my-microservice` chart into a multi-service `vsf-miniapp` platform supporting multiple languages and services.

---

## Table of Contents

1. [Overview](#overview)
2. [Migration Plan](#migration-plan)
3. [Step-by-Step Implementation](#step-by-step-implementation)
4. [AWS Secrets Manager Setup](#aws-secrets-manager-setup)
5. [CI/CD Pipeline Configuration](#cicd-pipeline-configuration)
6. [Verification and Testing](#verification-and-testing)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Current State
```
charts/my-microservice/          # Single service chart
applications/production/
  └── my-microservice.yaml       # Single application manifest
```

### Target State
```
charts/vsf-miniapp/              # Shared base chart
  └── ci/
      ├── service-a-production.yaml
      ├── service-b-production.yaml
      └── service-c-production.yaml

applications/production/
  ├── vsf-miniapp-service-a.yaml
  ├── vsf-miniapp-service-b.yaml
  └── vsf-miniapp-service-c.yaml
```

---

## Migration Plan

### Phase 1: Prepare Shared Chart
1. Rename `my-microservice` to `vsf-miniapp`
2. Update Chart.yaml metadata
3. Verify templates are parameterized

### Phase 2: Create Service-Specific Configurations
1. Create service-specific value files
2. Create ArgoCD application manifests
3. Set up AWS Secrets Manager secrets

### Phase 3: Deploy and Verify
1. Deploy Service A (Java)
2. Verify Linkerd mTLS
3. Verify AWS Secrets Manager integration
4. Deploy Service B (Node.js)
5. Deploy Service C (Python)

---

## Step-by-Step Implementation

### Step 1: Rename and Update Base Chart

```bash
# Navigate to repository
cd /home/vsf-longnd56-l/Documents/oNddleo/gitops

# Rename chart directory
git mv charts/my-microservice charts/vsf-miniapp

# Update Chart.yaml
cat > charts/vsf-miniapp/Chart.yaml <<EOF
apiVersion: v2
name: vsf-miniapp
description: Shared Helm chart for VSF Miniapp microservices platform
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - microservice
  - gitops
  - kubernetes
  - multi-language
maintainers:
  - name: Platform Team
    email: platform@example.com
home: https://github.com/oNddleo/gitops
sources:
  - https://github.com/oNddleo/gitops
EOF
```

### Step 2: Update values.yaml to Support Service Names

Edit `charts/vsf-miniapp/values.yaml` to add service name parameter at the top:

```yaml
# Service identity (override per service)
serviceName: "default-service"  # MUST be overridden in service-specific values
language: "generic"  # java, nodejs, python, etc.
runtime: ""  # openjdk-17, node-20, python-3.11, etc.

# Rest of your existing values...
replicaCount: 3
# ...
```

### Step 3: Update Chart Templates to Use serviceName

Update templates to use `{{ .Values.serviceName }}` where appropriate:

**charts/vsf-miniapp/templates/_helpers.tpl:**

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "vsf-miniapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We use serviceName to differentiate between services.
*/}}
{{- define "vsf-miniapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- printf "%s-%s" .Release.Name .Values.serviceName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s-%s" .Release.Name $name .Values.serviceName | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vsf-miniapp.labels" -}}
helm.sh/chart: {{ include "vsf-miniapp.chart" . }}
{{ include "vsf-miniapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
service: {{ .Values.serviceName }}
language: {{ .Values.language }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vsf-miniapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vsf-miniapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
service: {{ .Values.serviceName }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vsf-miniapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s" .Values.serviceName) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Chart name and version
*/}}
{{- define "vsf-miniapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
```

### Step 4: Create Service-Specific Value Files

Create value files for each service. See examples in `examples/multi-service/` directory:

```bash
# Create service-specific values directory
mkdir -p charts/vsf-miniapp/ci

# Copy example files (modify as needed)
cp examples/multi-service/service-a-production-values.yaml \
   charts/vsf-miniapp/ci/service-a-production.yaml

cp examples/multi-service/service-b-production-values.yaml \
   charts/vsf-miniapp/ci/service-b-production.yaml
```

**Important**: Update the following in each values file:
- `image.repository`: Your ECR registry URL
- `serviceAccount.annotations.eks.amazonaws.com/role-arn`: Your IAM role ARN
- `secretsManager.objects`: Your actual AWS Secrets Manager secret names
- `ingress.hosts`: Your actual domain names

### Step 5: Create ArgoCD Application Manifests

Create application manifests for each service per environment:

```bash
# Production
cp examples/multi-service/vsf-miniapp-service-a-production.yaml \
   applications/production/vsf-miniapp-service-a.yaml

# Staging (create similar files)
cat > applications/staging/vsf-miniapp-service-a.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vsf-miniapp-service-a-staging
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    environment: staging
    app: vsf-miniapp
    service: service-a
spec:
  project: default

  source:
    repoURL: https://github.com/oNddleo/gitops.git
    targetRevision: HEAD
    path: charts/vsf-miniapp
    helm:
      valueFiles:
        - ci/service-a-staging.yaml
      releaseName: service-a

  destination:
    server: https://kubernetes.default.svc
    namespace: staging

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

# Dev (create similar files)
cat > applications/dev/vsf-miniapp-service-a.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vsf-miniapp-service-a-dev
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    environment: dev
    app: vsf-miniapp
    service: service-a
spec:
  project: default

  source:
    repoURL: https://github.com/oNddleo/gitops.git
    targetRevision: HEAD
    path: charts/vsf-miniapp
    helm:
      valueFiles:
        - ci/service-a-dev.yaml
      releaseName: service-a

  destination:
    server: https://kubernetes.default.svc
    namespace: dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

### Step 6: Update App of Apps

Update the App of Apps manifests to include new applications:

**applications/app-of-apps-production.yaml:**

```yaml
# No changes needed - ArgoCD will automatically discover
# new application manifests in applications/production/
```

The directory-based discovery is already configured in your root app.

---

## AWS Secrets Manager Setup

### Step 1: Create IAM Policies and Roles

Create IAM policies for each service to access their secrets:

**Terraform example (recommended):**

```hcl
# Service A Secrets Reader Role
module "service_a_irsa" {
  source = "./terraform/modules/secrets-manager-irsa"

  cluster_name      = "gitops-eks-cluster"
  namespace         = "production"
  service_account   = "service-a"
  secret_arns = [
    "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:production/vsf-miniapp/service-a/*"
  ]
}

# Service B Secrets Reader Role
module "service_b_irsa" {
  source = "./terraform/modules/secrets-manager-irsa"

  cluster_name      = "gitops-eks-cluster"
  namespace         = "production"
  service_account   = "service-b"
  secret_arns = [
    "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:production/vsf-miniapp/service-b/*"
  ]
}
```

**AWS CLI alternative:**

```bash
# Service A IAM Policy
cat > service-a-secrets-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:production/vsf-miniapp/service-a/*"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name vsf-miniapp-service-a-secrets-reader \
  --policy-document file://service-a-secrets-policy.json

# Create IRSA role (requires OIDC provider)
eksctl create iamserviceaccount \
  --name service-a \
  --namespace production \
  --cluster gitops-eks-cluster \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/vsf-miniapp-service-a-secrets-reader \
  --approve \
  --override-existing-serviceaccounts
```

### Step 2: Create Secrets in AWS Secrets Manager

```bash
# Service A - PostgreSQL Database
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-a/database \
  --description "Database credentials for Service A production" \
  --secret-string '{
    "url": "postgresql://prod-db.rds.amazonaws.com:5432/servicea",
    "username": "service_a_user",
    "password": "CHANGE_ME_SECURE_PASSWORD",
    "maxPoolSize": "20"
  }' \
  --region us-east-1

# Service A - Kafka
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-a/kafka \
  --description "Kafka credentials for Service A production" \
  --secret-string '{
    "brokers": "kafka-1.prod.internal:9092,kafka-2.prod.internal:9092",
    "username": "service_a_kafka_user",
    "password": "CHANGE_ME_SECURE_PASSWORD"
  }' \
  --region us-east-1

# Service B - MongoDB
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-b/mongodb \
  --description "MongoDB credentials for Service B production" \
  --secret-string '{
    "connectionString": "mongodb://admin:CHANGE_ME@mongodb.prod.internal:27017/serviceb?authSource=admin",
    "database": "serviceb"
  }' \
  --region us-east-1

# Service B - Redis
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-b/redis \
  --description "Redis credentials for Service B production" \
  --secret-string '{
    "host": "redis.prod.internal",
    "port": "6379",
    "password": "CHANGE_ME_SECURE_PASSWORD"
  }' \
  --region us-east-1
```

---

## CI/CD Pipeline Configuration

### Update GitHub Actions Workflow

Update `.github/workflows/ci-build-deploy.yaml` to support multiple services:

**Key changes:**
1. Detect which service changed based on file paths
2. Build and push Docker images per service
3. Update service-specific value files

```yaml
name: CI/CD Pipeline - VSF Miniapp

on:
  push:
    branches: [main, develop]
    paths:
      - 'charts/vsf-miniapp/**'
      - 'applications/**'
      - 'services/**'  # Application source code
  pull_request:
    branches: [main, develop]

env:
  AWS_REGION: us-east-1
  HELM_VERSION: '3.14.0'

jobs:
  detect-changes:
    name: Detect Changed Services
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.filter.outputs.services }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |
            service-a:
              - 'services/service-a/**'
              - 'charts/vsf-miniapp/ci/service-a-*.yaml'
            service-b:
              - 'services/service-b/**'
              - 'charts/vsf-miniapp/ci/service-b-*.yaml'
            service-c:
              - 'services/service-c/**'
              - 'charts/vsf-miniapp/ci/service-c-*.yaml'

  build-service-a:
    name: Build Service A
    needs: detect-changes
    if: needs.detect-changes.outputs.services contains 'service-a'
    runs-on: ubuntu-latest
    steps:
      # Build steps for Service A
      # ...

  build-service-b:
    name: Build Service B
    needs: detect-changes
    if: needs.detect-changes.outputs.services contains 'service-b'
    runs-on: ubuntu-latest
    steps:
      # Build steps for Service B
      # ...
```

---

## Verification and Testing

### Step 1: Validate Helm Charts

```bash
# Lint all service configurations
for service in service-a service-b service-c; do
  echo "Validating ${service}..."
  helm lint charts/vsf-miniapp -f charts/vsf-miniapp/ci/${service}-production.yaml
  helm lint charts/vsf-miniapp -f charts/vsf-miniapp/ci/${service}-staging.yaml
  helm lint charts/vsf-miniapp -f charts/vsf-miniapp/ci/${service}-dev.yaml
done

# Template and validate
for service in service-a service-b service-c; do
  echo "Templating ${service}..."
  helm template ${service} charts/vsf-miniapp \
    -f charts/vsf-miniapp/ci/${service}-production.yaml \
    --namespace production \
    | kubectl apply --dry-run=client -f -
done
```

### Step 2: Deploy to Dev First

```bash
# Commit and push changes
git add .
git commit -m "feat: transform my-microservice to multi-service vsf-miniapp

- Rename chart to vsf-miniapp
- Add service-specific value files for service-a, service-b
- Create ArgoCD application manifests per service
- Configure AWS Secrets Manager integration per service
- Update CI/CD pipeline for multi-service support"

git push origin main

# Verify ArgoCD detected the changes
argocd app list

# Check Service A dev deployment
argocd app get vsf-miniapp-service-a-dev
argocd app sync vsf-miniapp-service-a-dev
argocd app wait vsf-miniapp-service-a-dev --health --timeout 300

# Check pods
kubectl get pods -n dev -l service=service-a

# Check Linkerd injection
kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].spec.containers[*].name}'
# Should show: service-a linkerd-proxy

# Check secrets mounted
POD=$(kubectl get pod -n dev -l service=service-a -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dev $POD -- ls -la /mnt/secrets

# Check synced Kubernetes Secret
kubectl get secret -n dev | grep service-a-secrets
kubectl describe secret service-a-secrets -n dev
```

### Step 3: Verify Linkerd mTLS

```bash
# Install Linkerd CLI if not already installed
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Check Linkerd data plane
linkerd check --proxy

# Verify Service A has mTLS enabled
linkerd viz stat deployment/service-a -n dev
# Output should show "SECURED" with 100% success rate

# View live traffic
linkerd viz tap deployment/service-a -n dev

# Check service-to-service communication
linkerd viz edges deployment -n dev
```

### Step 4: Test Secret Rotation

```bash
# Update secret in AWS
aws secretsmanager update-secret \
  --secret-id production/vsf-miniapp/service-a/database \
  --secret-string '{
    "url": "postgresql://prod-db.rds.amazonaws.com:5432/servicea",
    "username": "service_a_user",
    "password": "NEW_PASSWORD_FOR_TESTING",
    "maxPoolSize": "20"
  }' \
  --region us-east-1

# Wait 2 minutes for CSI driver to sync
sleep 120

# Check if Reloader triggered rolling update
kubectl get events -n production | grep Reloader

# Verify new pods have updated secret
POD=$(kubectl get pod -n production -l service=service-a -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n production $POD -- cat /mnt/secrets/database-password
# Should show: NEW_PASSWORD_FOR_TESTING
```

---

## Troubleshooting

### Issue: Pods Not Starting

**Symptoms:**
```bash
kubectl get pods -n production
# service-a-xxxxx   0/2     Init:0/1   0          30s
```

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production -c service-a
kubectl logs <pod-name> -n production -c linkerd-proxy
```

**Common causes:**
1. **Image pull errors**: Check ECR credentials and image exists
2. **Secret mount failures**: Verify IRSA role and SecretProviderClass
3. **Linkerd injection issues**: Check linkerd-proxy container logs

### Issue: Secrets Not Mounting

**Symptoms:**
```bash
kubectl exec -n production <pod> -- ls /mnt/secrets
# ls: cannot access '/mnt/secrets': No such file or directory
```

**Diagnosis:**
```bash
# Check SecretProviderClass
kubectl get secretproviderclass -n production
kubectl describe secretproviderclass service-a-secrets -n production

# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Check AWS provider logs
kubectl logs -n kube-system -l app.kubernetes.io/name=secrets-store-csi-driver-provider-aws

# Test IRSA permissions
kubectl run aws-cli --rm -it --image=amazon/aws-cli \
  --serviceaccount=service-a -n production -- \
  secretsmanager get-secret-value --secret-id production/vsf-miniapp/service-a/database --region us-east-1
```

**Solutions:**
1. Verify IAM role has correct trust policy for OIDC provider
2. Verify secret exists in AWS Secrets Manager
3. Check ServiceAccount has correct annotation
4. Verify CSI driver is running

### Issue: Linkerd mTLS Not Working

**Symptoms:**
```bash
linkerd viz stat deployment/service-a -n production
# Shows "NOT SECURED" or connection failures
```

**Diagnosis:**
```bash
# Check Linkerd control plane
linkerd check

# Check proxy injection
kubectl get pod <pod-name> -n production -o yaml | grep linkerd.io/inject

# Check namespace annotation
kubectl get namespace production -o yaml | grep linkerd.io/inject
```

**Solutions:**
1. Ensure pod has `linkerd.io/inject: enabled` annotation
2. Verify Linkerd control plane is healthy
3. Check trust anchor certificates are valid
4. Restart pods to re-inject proxy

### Issue: ArgoCD Not Syncing

**Symptoms:**
```bash
argocd app get vsf-miniapp-service-a-production
# Status: OutOfSync
```

**Diagnosis:**
```bash
argocd app get vsf-miniapp-service-a-production --show-operation
argocd app sync vsf-miniapp-service-a-production --dry-run
kubectl describe application vsf-miniapp-service-a-production -n argocd
```

**Solutions:**
1. Check repository credentials
2. Verify path in Application manifest
3. Check Helm values file exists
4. Force hard refresh: `argocd app refresh vsf-miniapp-service-a-production --hard`

---

## Summary

After completing this migration:

✅ **Shared Base Chart**: Single `vsf-miniapp` chart for all services
✅ **Multi-Language Support**: Java, Node.js, Python with service-specific configurations
✅ **Linkerd mTLS**: Automatic service-to-service encryption
✅ **AWS Secrets Manager**: Secure secret management with auto-rotation
✅ **App of Apps**: Hierarchical application management
✅ **GitOps**: Fully declarative, Git-driven deployments
✅ **CI/CD**: Automated build, test, and deploy pipelines
✅ **High Availability**: Multi-AZ deployment, HPA, PDB

Your platform is now **production-ready** and **scalable** for adding new services.
