# Multi-Service Architecture Summary

Quick reference guide for the VSF-Miniapp multi-service architecture implementation.

---

## Architecture Decision: Shared Base Chart vs Separate Charts

### ✅ Recommended: Shared Base Chart (Implemented)

**Structure:**
```
charts/vsf-miniapp/          # Single shared chart
  ├── Chart.yaml
  ├── values.yaml            # Common defaults
  ├── templates/             # Kubernetes manifests
  └── ci/                    # Service-specific values
      ├── service-a-production.yaml
      ├── service-a-staging.yaml
      ├── service-a-dev.yaml
      ├── service-b-production.yaml
      └── ...
```

**Advantages:**
- ✅ **DRY**: No duplication of Kubernetes manifests
- ✅ **Consistency**: All services use same deployment patterns
- ✅ **Easy maintenance**: Update one chart, all services benefit
- ✅ **Scalability**: Adding new services is trivial (just add values file)
- ✅ **Governance**: Enforce organizational standards across all services
- ✅ **Testing**: Test once, deploy many

**When to use:**
- Services share similar deployment requirements
- Organization values consistency over flexibility
- Team wants centralized control over infrastructure patterns
- Multiple services from the same platform/team

### ❌ Alternative: Separate Charts Per Service

**Structure:**
```
charts/
  ├── service-a/
  ├── service-b/
  └── service-c/
```

**Advantages:**
- ✅ Maximum flexibility per service
- ✅ Independent versioning
- ✅ No coupling between services

**Disadvantages:**
- ❌ Duplication of manifests
- ❌ Inconsistent patterns across services
- ❌ Hard to maintain (N charts to update)
- ❌ Harder to enforce standards

**When to use:**
- Services have vastly different deployment requirements
- Services owned by different teams with different standards
- Services need independent release cycles

---

## Multi-Language Support Strategy

### Language-Agnostic Base Chart + Language-Specific Values

**Base chart provides:**
- Deployment structure
- Service definition
- Security contexts (read-only filesystem, non-root user)
- Health probe endpoints
- Resource limits
- Linkerd injection
- AWS Secrets Manager integration
- HPA, PDB, affinity rules

**Service-specific values override:**
- Container image (Java JRE, Node.js runtime, Python interpreter)
- Port numbers (8080 for Java, 3000 for Node.js, 8000 for Python)
- Environment variables (JAVA_OPTS, NODE_ENV, PYTHONPATH)
- Health probe timing (Java slower startup)
- Resource requirements (Java needs more memory)

### Example Comparison

| Aspect | Java (Service A) | Node.js (Service B) | Python (Service C) |
|--------|------------------|---------------------|-------------------|
| **Port** | 8080 | 3000 | 8000 |
| **Memory Request** | 512Mi | 256Mi | 256Mi |
| **Memory Limit** | 1Gi | 512Mi | 768Mi |
| **Startup Time** | 60s | 15s | 20s |
| **Health Endpoint** | /actuator/health | /health/live | /health/live |
| **Common Config** | All use Linkerd mTLS, AWS Secrets Manager, HPA, PDB |

---

## Component Integration Matrix

| Component | Purpose | Configuration Location | How It Works |
|-----------|---------|----------------------|--------------|
| **Helm Chart** | Package & template | `charts/vsf-miniapp/` | Templates Kubernetes manifests with values |
| **Kustomize** | Environment overlays | `infrastructure/*/overlays/` | Infrastructure components only |
| **ArgoCD** | GitOps operator | `applications/` | Syncs Git state to cluster |
| **Linkerd** | mTLS service mesh | Pod annotation | Automatic sidecar injection |
| **Secrets Store CSI** | Mount secrets | Volume + SecretProviderClass | Mounts AWS secrets as files |
| **Reloader** | Auto-restart on config change | Pod annotation | Watches ConfigMap/Secret changes |
| **Traefik** | Ingress controller | IngressRoute CRD | Routes external traffic to services |

---

## Service Deployment Checklist

When adding a new service (e.g., Service D):

### 1. Create Service-Specific Value Files

```bash
# Create values for each environment
touch charts/vsf-miniapp/ci/service-d-dev.yaml
touch charts/vsf-miniapp/ci/service-d-staging.yaml
touch charts/vsf-miniapp/ci/service-d-production.yaml
```

**Required configurations:**
- [ ] `serviceName: service-d`
- [ ] `language: <java|nodejs|python|...>`
- [ ] `image.repository: YOUR_ECR_REGISTRY/vsf-miniapp-service-d`
- [ ] `service.targetPort: <port>`
- [ ] `resources.requests/limits`
- [ ] `env: []` (language-specific environment variables)
- [ ] `livenessProbe` and `readinessProbe`
- [ ] `secretsManager.objects: []` (AWS secret names)
- [ ] `ingress.hosts: [...]`

### 2. Create ArgoCD Application Manifests

```bash
# Create application manifest for each environment
touch applications/dev/vsf-miniapp-service-d.yaml
touch applications/staging/vsf-miniapp-service-d.yaml
touch applications/production/vsf-miniapp-service-d.yaml
```

**Required configurations:**
- [ ] `metadata.name: vsf-miniapp-service-d-<env>`
- [ ] `metadata.labels.service: service-d`
- [ ] `spec.source.path: charts/vsf-miniapp`
- [ ] `spec.source.helm.valueFiles: [ci/service-d-<env>.yaml]`
- [ ] `spec.destination.namespace: <env>`

### 3. Create AWS Secrets

```bash
# Create secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name production/vsf-miniapp/service-d/database \
  --secret-string '{"url":"...","username":"...","password":"..."}' \
  --region us-east-1
```

- [ ] Created secrets in AWS Secrets Manager
- [ ] Created IAM role with IRSA for ServiceAccount
- [ ] Verified IAM policy allows access to secrets

### 4. Commit and Deploy

```bash
git add .
git commit -m "feat: add Service D to vsf-miniapp platform"
git push

# Verify deployment
argocd app sync vsf-miniapp-service-d-production
argocd app wait vsf-miniapp-service-d-production --health --timeout 300
```

- [ ] Committed all changes to Git
- [ ] ArgoCD synced successfully
- [ ] Pods running (check with `kubectl get pods`)
- [ ] Linkerd mTLS enabled (check with `linkerd viz stat`)
- [ ] Secrets mounted (check with `kubectl exec ... ls /mnt/secrets`)
- [ ] Health checks passing
- [ ] Ingress accessible

---

## How Components Work Together

### Scenario: User Request Flow

```
1. External Request
   ↓
2. Traefik Ingress (TLS termination)
   ↓
3. Traefik → Service A Kubernetes Service
   ↓
4. Service (ClusterIP) → Pod
   ↓
5. Linkerd Proxy (mTLS encryption)
   ↓
6. Application Container
   |
   ├─ Reads ConfigMap (via envFrom)
   ├─ Reads Secrets (via envFrom from synced K8s Secret)
   └─ Reads Secret Files (via CSI volume mount)
```

### Scenario: Secret Update Flow

```
1. Engineer updates secret in AWS Secrets Manager
   ↓
2. CSI Driver polls every 2 minutes, detects change
   ↓
3. CSI Driver updates mounted files in /mnt/secrets/
   ↓
4. CSI Driver updates synced Kubernetes Secret
   ↓
5. Reloader watches Secret, detects change
   ↓
6. Reloader triggers rolling update of Deployment
   ↓
7. New pods start with updated secrets
```

### Scenario: Code Deployment Flow

```
1. Developer pushes code to main branch
   ↓
2. GitHub Actions CI triggers
   ↓
3. CI builds Docker image, pushes to ECR
   ↓
4. CI updates charts/vsf-miniapp/ci/service-a-production.yaml with new tag
   ↓
5. CI commits change back to Git
   ↓
6. ArgoCD detects Git change
   ↓
7. ArgoCD syncs new image tag to cluster
   ↓
8. Kubernetes performs rolling update
   ↓
9. Linkerd proxy automatically injected in new pods
   ↓
10. New pods come online with mTLS enabled
```

---

## Linkerd mTLS Implementation

### How mTLS Works

```
Service A → Service B Communication:

┌─────────────────────┐           ┌─────────────────────┐
│   Pod: Service A    │           │   Pod: Service B    │
│                     │           │                     │
│  ┌──────────────┐   │           │  ┌──────────────┐   │
│  │ App Container│   │           │  │ App Container│   │
│  │  (Java)      │   │           │  │  (Node.js)   │   │
│  │              │   │           │  │              │   │
│  │ http://      │───┼─────┐     │  │              │   │
│  │ service-b    │   │     │     │  │              │   │
│  └──────────────┘   │     │     │  └──────────────┘   │
│         ↓           │     │     │         ▲           │
│  ┌──────────────┐   │     │     │  ┌──────────────┐   │
│  │   Linkerd    │   │     │     │  │   Linkerd    │   │
│  │   Proxy      │───┼─────┴─────┼─▶│   Proxy      │   │
│  │  (mTLS)      │   │   HTTPS   │  │  (mTLS)      │   │
│  └──────────────┘   │   + Cert  │  └──────────────┘   │
└─────────────────────┘           └─────────────────────┘

Application code: Plain HTTP
Network traffic: Encrypted HTTPS with mutual TLS
```

### Configuration Required

**In Helm values (already configured):**
```yaml
podAnnotations:
  linkerd.io/inject: enabled
  config.linkerd.io/skip-outbound-ports: "5432,3306,6379,27017"  # Skip databases
```

**That's it!** Linkerd handles the rest automatically.

### Verification Commands

```bash
# Check if Linkerd proxy is injected
kubectl get pod <pod-name> -n production -o jsonpath='{.spec.containers[*].name}'
# Expected: service-a linkerd-proxy

# Check mTLS status
linkerd viz stat deployment/service-a -n production
# Expected: SECURED with 100% success rate

# View live traffic
linkerd viz tap deployment/service-a -n production
# Shows real-time requests with mTLS status

# View service topology
linkerd viz edges deployment -n production
# Shows which services communicate with each other
```

---

## AWS Secrets Manager Integration

### Architecture

```
AWS Secrets Manager
       ↓
    IRSA (IAM Role for Service Account)
       ↓
SecretProviderClass (defines what to fetch)
       ↓
CSI Driver (mounts secrets as files)
       ↓
Kubernetes Secret (synced for env vars)
       ↓
Application (reads via env vars or file mount)
```

### Files Involved

1. **AWS Secret** (created via AWS CLI/Console)
2. **IAM Role** (created via Terraform/IRSA)
3. **ServiceAccount** (in Helm chart)
   ```yaml
   serviceAccount:
     annotations:
       eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT_ID:role/..."
   ```
4. **SecretProviderClass** (in Helm chart template)
   ```yaml
   spec:
     provider: aws
     parameters:
       objects: |
         - objectName: "production/vsf-miniapp/service-a/database"
   ```
5. **Volume Mount** (in Deployment template)
   ```yaml
   volumes:
     - name: secrets-store
       csi:
         driver: secrets-store.csi.k8s.io
         volumeAttributes:
           secretProviderClass: service-a-secrets
   ```

### Secret Rotation

**Automatic (every 2 minutes):**
1. CSI driver polls AWS Secrets Manager
2. Detects changes and updates mounted files
3. Updates synced Kubernetes Secret
4. Reloader triggers rolling update
5. New pods get updated secrets

**Manual trigger:**
```bash
# Update secret in AWS
aws secretsmanager update-secret --secret-id ... --secret-string '{...}'

# Wait 2 minutes or force pod restart
kubectl rollout restart deployment/service-a -n production
```

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Check Command | Solution |
|---------|-------------|---------------|----------|
| Pods stuck in Init | Secret mount failure | `kubectl describe pod <pod>` | Verify IRSA, SecretProviderClass |
| No mTLS | Proxy not injected | `kubectl get pod -o yaml \| grep linkerd` | Add `linkerd.io/inject: enabled` |
| Secret not found | IRSA permissions | `kubectl run aws-cli ... secretsmanager get-secret-value` | Fix IAM policy |
| App won't sync | Helm values error | `argocd app get <app>` | Check Helm syntax, fix values file |
| 502 Bad Gateway | Service not ready | `kubectl get pods -l service=...` | Check readiness probe |
| ConfigMap changes ignored | Reloader not working | `kubectl logs -l app=reloader` | Verify Reloader annotation |

---

## Performance Characteristics

| Metric | Dev | Staging | Production |
|--------|-----|---------|-----------|
| **Replicas** | 1-2 | 2-5 | 3-20 (HPA) |
| **Resource Requests (Java)** | 100m CPU, 256Mi RAM | 200m CPU, 512Mi RAM | 250m CPU, 512Mi RAM |
| **Resource Requests (Node.js)** | 50m CPU, 128Mi RAM | 100m CPU, 256Mi RAM | 100m CPU, 256Mi RAM |
| **Sync Frequency (ArgoCD)** | 3 minutes | 3 minutes | 3 minutes |
| **Secret Rotation (CSI)** | 2 minutes | 2 minutes | 2 minutes |
| **Deployment Time** | ~2 min | ~3 min | ~5 min (rolling) |

---

## File Organization Reference

```
gitops/
├── charts/vsf-miniapp/                    # Shared Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                        # Common defaults
│   ├── templates/                         # Kubernetes manifest templates
│   │   ├── _helpers.tpl
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── secretproviderclass.yaml      # AWS Secrets Manager CSI
│   │   ├── configmap.yaml
│   │   ├── ingressroute.yaml             # Traefik ingress
│   │   ├── hpa.yaml
│   │   └── servicemonitor.yaml           # Prometheus metrics
│   └── ci/                                # Service-specific values
│       ├── service-a-dev.yaml
│       ├── service-a-staging.yaml
│       ├── service-a-production.yaml
│       ├── service-b-dev.yaml
│       └── ...
│
├── applications/                          # ArgoCD Application manifests
│   ├── infrastructure/                    # Infrastructure apps
│   │   ├── 00-project.yaml
│   │   ├── argocd-self-managed.yaml
│   │   ├── linkerd-crds.yaml
│   │   ├── linkerd-control-plane.yaml
│   │   ├── linkerd-viz.yaml
│   │   ├── secrets-store-csi-driver.yaml
│   │   ├── secrets-store-csi-driver-provider-aws.yaml
│   │   ├── traefik.yaml
│   │   └── reloader.yaml
│   ├── app-of-apps-dev.yaml              # Dev environment App of Apps
│   ├── app-of-apps-staging.yaml          # Staging environment App of Apps
│   ├── app-of-apps-production.yaml       # Production environment App of Apps
│   ├── dev/
│   │   ├── vsf-miniapp-service-a.yaml
│   │   └── vsf-miniapp-service-b.yaml
│   ├── staging/
│   │   ├── vsf-miniapp-service-a.yaml
│   │   └── vsf-miniapp-service-b.yaml
│   └── production/
│       ├── vsf-miniapp-service-a.yaml
│       └── vsf-miniapp-service-b.yaml
│
├── infrastructure/                        # Infrastructure Kustomize + Helm
│   ├── argocd/
│   ├── linkerd/
│   ├── linkerd-viz/
│   ├── traefik/
│   ├── secrets-store-csi/
│   └── reloader/
│
├── bootstrap/                             # Bootstrap scripts
│   ├── install.sh
│   ├── argocd-namespace.yaml
│   └── root-app.yaml                     # Root App of Apps
│
└── .github/workflows/                     # CI/CD pipelines
    ├── ci-build-deploy.yaml
    ├── pr-validation.yaml
    └── infrastructure-sync.yaml
```

---

## Next Steps

1. **Review** existing implementation in your repository
2. **Read** ARCHITECTURE_GUIDE.md for detailed explanations
3. **Follow** IMPLEMENTATION_GUIDE.md for step-by-step migration
4. **Reference** examples in `examples/multi-service/` directory
5. **Deploy** to dev environment first
6. **Verify** Linkerd mTLS and AWS Secrets Manager integration
7. **Promote** to staging and production

Your platform is **production-ready** with excellent foundations! 🚀
