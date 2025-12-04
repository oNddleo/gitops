# GitOps Platform Architecture Guide

## Multi-Service Microservice Architecture

This guide explains how to structure multiple services within the vsf-miniapp microservice platform using the shared Helm chart approach.

---

## Table of Contents

1. [Multi-Service Strategy](#multi-service-strategy)
2. [Multi-Language Support](#multi-language-support)
3. [Linkerd mTLS Integration](#linkerd-mtls-integration)
4. [AWS Secrets Manager Integration](#aws-secrets-manager-integration)
5. [App of Apps Pattern](#app-of-apps-pattern)
6. [Complete Example: Adding a New Service](#complete-example-adding-a-new-service)

---

## 1. Multi-Service Strategy

### Recommended Approach: Shared Base Chart

Use a single, parameterized Helm chart for all services with service-specific value files.

**Advantages:**
- **DRY principle**: No duplication of Kubernetes manifests
- **Consistency**: All services follow the same deployment patterns
- **Easy maintenance**: Update one chart, benefits all services
- **Scalability**: Adding new services is trivial

**Directory Structure:**
```
charts/vsf-miniapp/
├── Chart.yaml
├── values.yaml                        # Default values (common configuration)
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   ├── secretproviderclass.yaml
│   ├── configmap.yaml
│   ├── ingressroute.yaml
│   ├── hpa.yaml
│   └── servicemonitor.yaml
└── ci/
    ├── service-a-dev.yaml            # Service A development overrides
    ├── service-a-staging.yaml        # Service A staging overrides
    ├── service-a-production.yaml     # Service A production overrides
    ├── service-b-dev.yaml            # Service B development overrides
    ├── service-b-staging.yaml        # Service B staging overrides
    └── service-b-production.yaml     # Service B production overrides
```

**Application Manifests:**
```
applications/
├── production/
│   ├── vsf-miniapp-service-a.yaml    # Points to charts/vsf-miniapp + ci/service-a-production.yaml
│   └── vsf-miniapp-service-b.yaml    # Points to charts/vsf-miniapp + ci/service-b-production.yaml
├── staging/
│   ├── vsf-miniapp-service-a.yaml
│   └── vsf-miniapp-service-b.yaml
└── dev/
    ├── vsf-miniapp-service-a.yaml
    └── vsf-miniapp-service-b.yaml
```

---

## 2. Multi-Language Support

### Strategy: Language-Agnostic Base Chart with Runtime Overrides

The base chart (`charts/vsf-miniapp`) is **language-agnostic**. Language-specific configurations are defined in service-specific value files.

**Common Base Chart Elements (Language-Agnostic):**
- Deployment structure
- Service definition
- Security contexts
- Health probes endpoints
- Resource limits
- Linkerd injection
- AWS Secrets Manager integration
- HPA configuration

**Language-Specific Configurations (in Values Files):**
- Container image (Java JRE, Node.js, Python base)
- Port numbers (8080 for Java, 3000 for Node.js, 8000 for Python)
- Environment variables (JAVA_OPTS, NODE_ENV, PYTHONPATH)
- Health probe paths
- Resource requirements (Java needs more memory)
- Startup/liveness/readiness probe timing

### Example: Service-Specific Values for Different Languages

**Java Service (service-a-production.yaml):**
```yaml
# Service A - Java Spring Boot Application
serviceName: service-a
language: java
runtime: openjdk-17

image:
  repository: YOUR_ECR_REGISTRY/vsf-miniapp-service-a
  tag: "1.0.0"
  pullPolicy: IfNotPresent

replicaCount: 5

# Java-specific configurations
service:
  port: 80
  targetPort: 8080  # Spring Boot default

env:
  - name: JAVA_OPTS
    value: "-Xmx512m -Xms256m -XX:+UseG1GC"
  - name: SPRING_PROFILES_ACTIVE
    value: "production"
  - name: SERVER_PORT
    value: "8080"

resources:
  requests:
    cpu: 250m
    memory: 512Mi  # Java needs more memory
  limits:
    cpu: 1000m
    memory: 1Gi

# Health probes for Spring Boot Actuator
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  initialDelaySeconds: 60  # Java startup is slower
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

# Service-specific secrets from AWS Secrets Manager
secretsManager:
  enabled: true
  region: us-east-1
  objects:
    - objectName: "production/vsf-miniapp/service-a/database"
      objectType: "secretsmanager"
      jmesPath:
        - path: url
          objectAlias: database-url
        - path: username
          objectAlias: database-username
        - path: password
          objectAlias: database-password
    - objectName: "production/vsf-miniapp/service-a/kafka"
      objectType: "secretsmanager"
      jmesPath:
        - path: brokers
          objectAlias: kafka-brokers
        - path: username
          objectAlias: kafka-username
        - path: password
          objectAlias: kafka-password

ingress:
  enabled: true
  hosts:
    - host: service-a.vsf-miniapp.com
      paths:
        - path: /api/v1/service-a
          pathType: Prefix
```

**Node.js Service (service-b-production.yaml):**
```yaml
# Service B - Node.js Express Application
serviceName: service-b
language: nodejs
runtime: node-20

image:
  repository: YOUR_ECR_REGISTRY/vsf-miniapp-service-b
  tag: "1.0.0"
  pullPolicy: IfNotPresent

replicaCount: 3

# Node.js-specific configurations
service:
  port: 80
  targetPort: 3000  # Express default

env:
  - name: NODE_ENV
    value: "production"
  - name: PORT
    value: "3000"
  - name: NODE_OPTIONS
    value: "--max-old-space-size=512"

resources:
  requests:
    cpu: 100m
    memory: 256Mi  # Node.js is lighter
  limits:
    cpu: 500m
    memory: 512Mi

# Health probes for Express
livenessProbe:
  httpGet:
    path: /health/live
    port: 3000
  initialDelaySeconds: 15  # Node.js starts faster
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health/ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3

# Service-specific secrets
secretsManager:
  enabled: true
  region: us-east-1
  objects:
    - objectName: "production/vsf-miniapp/service-b/mongodb"
      objectType: "secretsmanager"
      jmesPath:
        - path: connectionString
          objectAlias: mongodb-uri
    - objectName: "production/vsf-miniapp/service-b/redis"
      objectType: "secretsmanager"
      jmesPath:
        - path: host
          objectAlias: redis-host
        - path: password
          objectAlias: redis-password

ingress:
  enabled: true
  hosts:
    - host: service-b.vsf-miniapp.com
      paths:
        - path: /api/v1/service-b
          pathType: Prefix
```

**Python Service (service-c-production.yaml):**
```yaml
# Service C - Python FastAPI Application
serviceName: service-c
language: python
runtime: python-3.11

image:
  repository: YOUR_ECR_REGISTRY/vsf-miniapp-service-c
  tag: "1.0.0"
  pullPolicy: IfNotPresent

replicaCount: 3

# Python-specific configurations
service:
  port: 80
  targetPort: 8000  # FastAPI/Uvicorn default

env:
  - name: PYTHONUNBUFFERED
    value: "1"
  - name: WORKERS
    value: "4"
  - name: PORT
    value: "8000"

resources:
  requests:
    cpu: 150m
    memory: 256Mi
  limits:
    cpu: 750m
    memory: 768Mi

# Health probes for FastAPI
livenessProbe:
  httpGet:
    path: /health/live
    port: 8000
  initialDelaySeconds: 20
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3

# Service-specific secrets
secretsManager:
  enabled: true
  region: us-east-1
  objects:
    - objectName: "production/vsf-miniapp/service-c/postgres"
      objectType: "secretsmanager"
      jmesPath:
        - path: host
          objectAlias: postgres-host
        - path: database
          objectAlias: postgres-database
        - path: username
          objectAlias: postgres-username
        - path: password
          objectAlias: postgres-password

ingress:
  enabled: true
  hosts:
    - host: service-c.vsf-miniapp.com
      paths:
        - path: /api/v1/service-c
          pathType: Prefix
```

---

## 3. Linkerd mTLS Integration

### How Linkerd mTLS Works in This Platform

Linkerd provides **automatic mutual TLS (mTLS)** for all service-to-service communication without requiring application code changes.

**Key Components:**

1. **Trust Anchor Certificate**: Root CA certificate stored in `infrastructure/linkerd/base/linkerd-certificates.yaml`
2. **Identity Issuer**: Linkerd control plane manages short-lived certificates for each pod
3. **Proxy Injection**: Sidecar automatically injected into pods with `linkerd.io/inject: enabled`

### Configuration in Helm Chart

The base chart already includes Linkerd configuration in `values.yaml`:

```yaml
# Pod annotations
podAnnotations:
  # Enable Linkerd sidecar injection
  linkerd.io/inject: enabled

  # Skip database ports from being proxied (databases handle their own TLS)
  config.linkerd.io/skip-outbound-ports: "5432,3306,6379,27017,9092"

  # Enable Reloader for ConfigMap/Secret changes
  reloader.stakater.com/auto: "true"
```

### Service-to-Service Communication with mTLS

When Service A calls Service B:

```
┌──────────────┐                  ┌──────────────┐
│  Service A   │                  │  Service B   │
│  ┌────────┐  │                  │  ┌────────┐  │
│  │  App   │  │  Plain HTTP      │  │  App   │  │
│  │Process │──┼──────────────────┼─▶│Process │  │
│  └────────┘  │                  │  └────────┘  │
│      │       │                  │      ▲       │
│      ▼       │                  │      │       │
│  ┌────────┐  │                  │  ┌────────┐  │
│  │Linkerd │  │  mTLS encrypted  │  │Linkerd │  │
│  │ Proxy  │──┼──────────────────┼─▶│ Proxy  │  │
│  └────────┘  │                  │  └────────┘  │
└──────────────┘                  └──────────────┘
```

**Application code remains HTTP** - Linkerd handles TLS automatically.

### Verifying mTLS

```bash
# Check if pod has Linkerd proxy injected
kubectl get pod <pod-name> -n production -o jsonpath='{.spec.containers[*].name}'
# Should show: service-a linkerd-proxy

# Check mTLS status
linkerd viz stat deployment/service-a -n production
# Should show "SECURED" in the output

# View live traffic with mTLS metrics
linkerd viz tap deployment/service-a -n production
```

### Database Connection Exclusion

Since databases (PostgreSQL, MySQL, MongoDB) manage their own TLS, we exclude their ports from Linkerd proxying:

```yaml
podAnnotations:
  config.linkerd.io/skip-outbound-ports: "5432,3306,6379,27017,9092"
```

This ensures:
- Database clients connect directly to databases
- Database native TLS is used
- No double encryption overhead

---

## 4. AWS Secrets Manager Integration

### Architecture

```
┌─────────────────────┐
│  AWS Secrets Manager│
│  ┌───────────────┐  │
│  │ prod/service-a│  │
│  │ /database     │  │
│  └───────────────┘  │
└──────────┬──────────┘
           │
           │ IRSA (IAM Roles for Service Accounts)
           │
           ▼
┌─────────────────────────────────────────────┐
│  Kubernetes Cluster                         │
│  ┌───────────────────────────────────────┐  │
│  │ Pod: service-a                        │  │
│  │  ┌─────────────────┐                  │  │
│  │  │ CSI Driver      │                  │  │
│  │  │ Volume Mount    │                  │  │
│  │  │ /mnt/secrets/   │                  │  │
│  │  │  ├─ db-url      │                  │  │
│  │  │  ├─ db-user     │                  │  │
│  │  │  └─ db-password │                  │  │
│  │  └─────────────────┘                  │  │
│  │         │                             │  │
│  │         ▼                             │  │
│  │  ┌─────────────────┐                  │  │
│  │  │ Kubernetes      │                  │  │
│  │  │ Secret (synced) │ ◀─── Reloader    │  │
│  │  │ env vars        │      watches     │  │
│  │  └─────────────────┘                  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### How It Works

1. **SecretProviderClass** defines which secrets to fetch from AWS Secrets Manager
2. **CSI Driver** mounts secrets as files in `/mnt/secrets/`
3. **Kubernetes Secret** is created by syncing CSI volume contents
4. **Application** reads secrets via environment variables from the synced Secret
5. **Reloader** watches the Secret and triggers rolling update when secrets change

### Complete Example: Service A with Database Credentials

**Step 1: Create Secret in AWS Secrets Manager**

```bash
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-a/database \
  --description "Database credentials for Service A production" \
  --secret-string '{
    "url": "postgresql://prod-db.rds.amazonaws.com:5432/servicea",
    "username": "service_a_user",
    "password": "super-secret-password"
  }' \
  --region us-east-1
```

**Step 2: Configure in Helm Values (service-a-production.yaml)**

```yaml
# Service Account with IRSA annotation
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/vsf-miniapp-secrets-reader"

# AWS Secrets Manager configuration
secretsManager:
  enabled: true
  region: us-east-1
  mountPath: /mnt/secrets

  # Define secrets to fetch
  objects:
    - objectName: "production/vsf-miniapp/service-a/database"
      objectType: "secretsmanager"
      jmesPath:
        - path: url
          objectAlias: database-url
        - path: username
          objectAlias: database-username
        - path: password
          objectAlias: database-password

  # Sync to Kubernetes Secret for environment variables
  syncToKubernetesSecret: true
  secretData:
    - objectName: database-url
      key: DATABASE_URL
    - objectName: database-username
      key: DATABASE_USERNAME
    - objectName: database-password
      key: DATABASE_PASSWORD

# Reference the synced secret in environment variables
envFrom:
  - configMapRef:
      name: service-a-config
  - secretRef:
      name: service-a-secrets  # Auto-created by CSI driver
```

**Step 3: SecretProviderClass Template (Already in Chart)**

The chart template `templates/secretproviderclass.yaml` automatically generates:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: service-a-secrets
  namespace: production
spec:
  provider: aws
  parameters:
    region: us-east-1
    objects: |
      - objectName: "production/vsf-miniapp/service-a/database"
        objectType: "secretsmanager"
        jmesPath:
          - path: url
            objectAlias: database-url
          - path: username
            objectAlias: database-username
          - path: password
            objectAlias: database-password

  # Sync to Kubernetes Secret
  secretObjects:
    - secretName: service-a-secrets
      type: Opaque
      annotations:
        reloader.stakater.com/match: "true"  # Reloader watches this
      data:
        - objectName: database-url
          key: DATABASE_URL
        - objectName: database-username
          key: DATABASE_USERNAME
        - objectName: database-password
          key: DATABASE_PASSWORD
```

**Step 4: Deployment Volume Mount (Already in Chart)**

The deployment template automatically mounts the CSI volume:

```yaml
spec:
  serviceAccountName: service-a  # Has IRSA annotation
  containers:
    - name: service-a
      envFrom:
        - secretRef:
            name: service-a-secrets  # Synced from CSI
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
          secretProviderClass: service-a-secrets
```

### Secret Rotation

**Automatic rotation every 2 minutes** (configurable):

1. CSI driver polls AWS Secrets Manager every 2 minutes
2. If secret changes, CSI driver updates the mounted files
3. CSI driver updates the synced Kubernetes Secret
4. Reloader detects Secret change and triggers rolling update
5. New pods get the updated secrets

**Manual secret rotation:**

```bash
# Update secret in AWS
aws secretsmanager update-secret \
  --secret-id production/vsf-miniapp/service-a/database \
  --secret-string '{"url":"...","username":"...","password":"new-password"}' \
  --region us-east-1

# Wait 2 minutes for CSI driver to sync
# Reloader will automatically trigger rolling update
```

---

## 5. App of Apps Pattern

### Hierarchy

```
bootstrap/root-app.yaml (Root Application)
│
├─▶ applications/infrastructure/ (Infrastructure Apps)
│   ├── 00-project.yaml
│   ├── argocd-self-managed.yaml
│   ├── linkerd-crds.yaml
│   ├── linkerd-control-plane.yaml
│   ├── linkerd-viz.yaml
│   ├── secrets-store-csi-driver.yaml
│   ├── secrets-store-csi-driver-provider-aws.yaml
│   ├── traefik.yaml
│   └── reloader.yaml
│
├─▶ applications/app-of-apps-dev.yaml (Dev Environment Apps)
│   └─▶ applications/dev/
│       ├── vsf-miniapp-service-a.yaml
│       └── vsf-miniapp-service-b.yaml
│
├─▶ applications/app-of-apps-staging.yaml (Staging Environment Apps)
│   └─▶ applications/staging/
│       ├── vsf-miniapp-service-a.yaml
│       └── vsf-miniapp-service-b.yaml
│
└─▶ applications/app-of-apps-production.yaml (Production Environment Apps)
    └─▶ applications/production/
        ├── vsf-miniapp-service-a.yaml
        └── vsf-miniapp-service-b.yaml
```

### Benefits

1. **Single entry point**: Deploy entire platform with one Application
2. **Automatic synchronization**: Changes to child apps are detected
3. **Cascading deletion**: Delete root app removes all child apps
4. **Environment isolation**: Each environment has its own App of Apps

---

## 6. Complete Example: Adding a New Service

Let's add **Service C** (Python FastAPI) to the vsf-miniapp platform.

### Step 1: Create Service-Specific Value Files

Create `charts/vsf-miniapp/ci/service-c-production.yaml`:

```yaml
serviceName: service-c
language: python

image:
  repository: YOUR_ECR_REGISTRY/vsf-miniapp-service-c
  tag: "1.0.0"

replicaCount: 3

service:
  port: 80
  targetPort: 8000

env:
  - name: PYTHONUNBUFFERED
    value: "1"
  - name: PORT
    value: "8000"

resources:
  requests:
    cpu: 150m
    memory: 256Mi
  limits:
    cpu: 750m
    memory: 768Mi

livenessProbe:
  httpGet:
    path: /health/live
    port: 8000
  initialDelaySeconds: 20
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5

secretsManager:
  enabled: true
  region: us-east-1
  objects:
    - objectName: "production/vsf-miniapp/service-c/postgres"
      objectType: "secretsmanager"
      jmesPath:
        - path: host
          objectAlias: postgres-host
        - path: database
          objectAlias: postgres-database
        - path: username
          objectAlias: postgres-username
        - path: password
          objectAlias: postgres-password
  syncToKubernetesSecret: true
  secretData:
    - objectName: postgres-host
      key: POSTGRES_HOST
    - objectName: postgres-database
      key: POSTGRES_DATABASE
    - objectName: postgres-username
      key: POSTGRES_USERNAME
    - objectName: postgres-password
      key: POSTGRES_PASSWORD

ingress:
  enabled: true
  hosts:
    - host: service-c.vsf-miniapp.com
      paths:
        - path: /api/v1/service-c
          pathType: Prefix
```

### Step 2: Create ArgoCD Application Manifest

Create `applications/production/vsf-miniapp-service-c.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vsf-miniapp-service-c-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    environment: production
    app: vsf-miniapp
    service: service-c
spec:
  project: default

  source:
    repoURL: https://github.com/oNddleo/gitops.git
    targetRevision: HEAD
    path: charts/vsf-miniapp
    helm:
      valueFiles:
        - ci/service-c-production.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: production

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
```

### Step 3: Create AWS Secret

```bash
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-c/postgres \
  --secret-string '{
    "host": "prod-postgres.rds.amazonaws.com",
    "database": "servicec",
    "username": "service_c_user",
    "password": "secret-password"
  }' \
  --region us-east-1
```

### Step 4: Commit and Push

```bash
git add charts/vsf-miniapp/ci/service-c-production.yaml
git add applications/production/vsf-miniapp-service-c.yaml
git commit -m "feat: add Service C (Python FastAPI) to production"
git push
```

### Step 5: Verify Deployment

```bash
# Check ArgoCD Application
argocd app get vsf-miniapp-service-c-production

# Check pods
kubectl get pods -n production -l app.kubernetes.io/name=vsf-miniapp,service=service-c

# Check Linkerd mTLS
linkerd viz stat deployment/service-c -n production

# Check secrets mounted
kubectl exec -n production <service-c-pod> -- ls -la /mnt/secrets

# Check synced Kubernetes Secret
kubectl get secret service-c-secrets -n production
```

---

## Summary

**Your platform already has excellent foundations.** Here's what you need to do:

1. **Rename** `charts/my-microservice` to `charts/vsf-miniapp`
2. **Create service-specific value files** for each service (service-a, service-b, etc.)
3. **Create ArgoCD Application manifests** for each service per environment
4. **Create AWS Secrets** for each service
5. **Commit and push** - ArgoCD will handle the rest

**Key Principles:**
- ✅ Use shared base chart for consistency
- ✅ Service-specific values for differentiation
- ✅ Linkerd mTLS is automatic (just add annotation)
- ✅ AWS Secrets Manager via CSI driver
- ✅ Reloader for automatic updates
- ✅ App of Apps for hierarchical management

This architecture is **production-ready**, **scalable**, and follows **GitOps best practices**.
