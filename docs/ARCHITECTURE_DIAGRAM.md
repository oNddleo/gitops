# VSF-Miniapp Multi-Service Architecture Diagrams

Visual representation of the complete GitOps platform architecture.

---

## 1. Complete Platform Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          DEVELOPER WORKFLOW                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                     ┌──────────────┼──────────────┐
                     ▼              ▼              ▼
              ┌──────────┐   ┌──────────┐   ┌──────────┐
              │ Service A│   │ Service B│   │ Service C│
              │  (Java)  │   │ (Node.js)│   │ (Python) │
              │   Code   │   │   Code   │   │   Code   │
              └──────────┘   └──────────┘   └──────────┘
                     │              │              │
                     └──────────────┼──────────────┘
                                    ▼
                        ┌───────────────────────┐
                        │   Git Repository      │
                        │  (Single Source of    │
                        │       Truth)          │
                        │                       │
                        │ • charts/vsf-miniapp/ │
                        │ • applications/       │
                        │ • infrastructure/     │
                        └───────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
        ┌───────────────────────┐       ┌──────────────────────┐
        │  GitHub Actions CI    │       │      ArgoCD          │
        │  ┌─────────────────┐  │       │   (GitOps Operator)  │
        │  │ 1. Lint & Test  │  │       │                      │
        │  │ 2. Build Image  │  │       │  Continuous Sync     │
        │  │ 3. Push to ECR  │  │       │  ┌────────────────┐  │
        │  │ 4. Update Git   │──┼───────┼─▶│ Detect Changes │  │
        │  └─────────────────┘  │       │  │ Apply to       │  │
        └───────────────────────┘       │  │ Cluster        │  │
                                        │  └────────────────┘  │
                                        └──────────────────────┘
                                                    │
                                                    ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         AWS EKS CLUSTER                                     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    INFRASTRUCTURE LAYER                             │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │   │
│  │  │ Linkerd  │  │ Traefik  │  │  CSI     │  │ Reloader │             │   │
│  │  │ (mTLS)   │  │ Ingress  │  │ Driver   │  │          │             │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     APPLICATION LAYER                               │   │
│  │                                                                     │   │
│  │  ┌──────────────────┐   ┌──────────────────┐   ┌─────────────────┐  │   │
│  │  │ Namespace: prod  │   │ Namespace: stg   │   │ Namespace: dev  │  │   │
│  │  │                  │   │                  │   │                 │  │   │
│  │  │ ┌─────────────┐  │   │ ┌─────────────┐  │   │ ┌────────────┐  │  │   │
│  │  │ │  Service A  │  │   │ │  Service A  │  │   │ │ Service A  │ │   │   │
│  │  │ │   (Java)    │  │   │ │   (Java)    │  │   │ │  (Java)    │ │   │   │
│  │  │ │   ┌─────┐   │  │   │ │   ┌─────┐   │  │   │ │  ┌─────┐   │ │   │   │
│  │  │ │   │ App │   │  │   │ │   │ App │   │  │   │ │  │ App │   │ │   │   │
│  │  │ │   └─────┘   │  │   │ │   └─────┘   │  │   │ │  └─────┘   │ │   │   │
│  │  │ │   ┌─────┐   │  │   │ │   ┌─────┐   │  │   │ │  ┌─────┐   │ │   │   │
│  │  │ │   │Proxy│   │  │   │ │   │Proxy│   │  │   │ │  │Proxy│   │ │   │   │
│  │  │ │   └─────┘   │  │   │ │   └─────┘   │  │   │ │  └─────┘   │ │   │   │
│  │  │ │             │  │   │ │             │  │   │ │            │ │   │   │
│  │  │ ┌─────────────┐  │   │ ┌─────────────┐  │ │ │ ┌────────────┐ │   │   │
│  │  │ │  Service B  │  │   │ │  Service B  │  │   │ │  Service B │ ││   │
│  │  │ │   (Node.js) │  │   │ │   (Node.js) │  │   │ │  (Node.js) │ ││   │
│  │  │ │   ┌─────┐   │  │   │ │   ┌─────┐   │  │   │ │  ┌─────┐   │ ││   │
│  │  │ │   │ App │   │  │   │ │   │ App │   │  │   │ │  │ App │   │ ││   │
│  │  │ │   └─────┘   │  │   │ │   └─────┘   │  │   │ │  └─────┘   │ ││   │
│  │  │ │   ┌─────┐   │  │   │ │   ┌─────┐   │  │   │ │  ┌─────┐   │ ││   │
│  │  │ │   │Proxy│   │  │   │ │   │Proxy│   │  │   │ │  │Proxy│   │ ││   │
│  │  │ │   └─────┘   │  │   │ │   └─────┘   │  │   │ │  └─────┘   │ ││   │
│  │  │ └─────────────┘  │   │ └─────────────┘  │   │ └────────────┘ ││   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     EXTERNAL INTEGRATIONS                           │   │
│  │                                                                      │   │
│  │  ┌──────────────────┐         ┌────────────────────┐               │   │
│  │  │ AWS Secrets      │         │ AWS ECR            │               │   │
│  │  │ Manager          │◀────────│ (Container Images) │               │   │
│  │  │                  │   IRSA  │                    │               │   │
│  │  │ - service-a/db   │         │ - service-a:1.0.0  │               │   │
│  │  │ - service-b/mongo│         │ - service-b:1.0.0  │               │   │
│  │  │ - service-c/pg   │         │ - service-c:1.0.0  │               │   │
│  │  └──────────────────┘         └────────────────────┘               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
                            ┌───────┴────────┐
                            │  External      │
                            │  Users/API     │
                            │  Clients       │
                            └────────────────┘
```

---

## 2. App of Apps Hierarchy

```
┌────────────────────────────────────────────────────────────────────┐
│                    bootstrap/root-app.yaml                          │
│                   (Root Application)                                │
└────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
        ┌───────────────────────┴───────────────────────┐
        │                                               │
        ▼                                               ▼
┌──────────────────────┐                   ┌───────────────────────┐
│ Infrastructure Apps  │                   │  Environment Apps     │
│ (Always Deployed)    │                   │  (Per Environment)    │
└──────────────────────┘                   └───────────────────────┘
        │                                               │
        ├─▶ 00-project.yaml                           ├─▶ app-of-apps-dev.yaml
        ├─▶ argocd-self-managed.yaml                  │       │
        ├─▶ linkerd-crds.yaml                         │       ├─▶ dev/vsf-miniapp-service-a.yaml
        ├─▶ linkerd-control-plane.yaml                │       └─▶ dev/vsf-miniapp-service-b.yaml
        ├─▶ linkerd-viz.yaml                          │
        ├─▶ secrets-store-csi-driver.yaml             ├─▶ app-of-apps-staging.yaml
        ├─▶ secrets-store-csi-driver-provider-aws.yaml│       │
        ├─▶ traefik.yaml                              │       ├─▶ staging/vsf-miniapp-service-a.yaml
        └─▶ reloader.yaml                             │       └─▶ staging/vsf-miniapp-service-b.yaml
                                                       │
                                                       └─▶ app-of-apps-production.yaml
                                                               │
                                                               ├─▶ production/vsf-miniapp-service-a.yaml
                                                               └─▶ production/vsf-miniapp-service-b.yaml
```

---

## 3. Service-to-Service Communication with Linkerd mTLS

```
┌─────────────────────────────────────────────────────────────────────────┐
│                  USER REQUEST FLOW                                       │
└─────────────────────────────────────────────────────────────────────────┘

1. External Request
        │
        ▼
┌───────────────────┐
│  Traefik Ingress  │  ◀── TLS Termination (HTTPS)
│  (Load Balancer)  │      Certificate from cert-manager
└───────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  Service A Pod                                                │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐     │
│  │ Linkerd Proxy (Ingress)                             │     │
│  │ - Decrypts incoming traffic                         │     │
│  │ - Validates mTLS certificate                        │     │
│  │ - Routes to app container                           │     │
│  └─────────────────────────────────────────────────────┘     │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────┐     │
│  │ Application Container (Java)                        │     │
│  │ - Port 8080 (HTTP, not HTTPS!)                      │     │
│  │ - Receives plain HTTP request                       │     │
│  │ - Makes HTTP call to Service B: http://service-b   │     │
│  └─────────────────────────────────────────────────────┘     │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────┐     │
│  │ Linkerd Proxy (Egress)                              │     │
│  │ - Intercepts outbound HTTP to service-b            │     │
│  │ - Encrypts with mTLS                                │     │
│  │ - Adds Linkerd identity headers                     │     │
│  └─────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
                          │
                          │ mTLS Encrypted
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│  Service B Pod                                                │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐     │
│  │ Linkerd Proxy (Ingress)                             │     │
│  │ - Validates Service A's mTLS certificate            │     │
│  │ - Decrypts traffic                                  │     │
│  │ - Routes to app container                           │     │
│  └─────────────────────────────────────────────────────┘     │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────┐     │
│  │ Application Container (Node.js)                     │     │
│  │ - Port 3000 (HTTP, not HTTPS!)                      │     │
│  │ - Receives plain HTTP request                       │     │
│  │ - Processes request and returns response            │     │
│  └─────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘

KEY POINTS:
✅ Application code uses HTTP (not HTTPS)
✅ Linkerd proxies handle all mTLS automatically
✅ No code changes required for security
✅ Zero-trust networking: every connection is encrypted
```

---

## 4. AWS Secrets Manager Integration Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                    AWS SECRETS MANAGER                                │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ production/vsf-miniapp/service-a/database                   │     │
│  │  {                                                          │     │
│  │    "url": "postgresql://prod-db:5432/servicea",            │     │
│  │    "username": "service_a_user",                           │     │
│  │    "password": "super-secret-password"                     │     │
│  │  }                                                          │     │
│  └─────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ IRSA (IAM Role for Service Account)
                                    │ arn:aws:iam::ACCOUNT:role/service-a-secrets-reader
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│  KUBERNETES CLUSTER                                                   │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐      │
│  │ SecretProviderClass: service-a-secrets                     │      │
│  │  - Defines which secrets to fetch                          │      │
│  │  - Maps secret JSON fields to file names                   │      │
│  │  - Configures sync to Kubernetes Secret                    │      │
│  └────────────────────────────────────────────────────────────┘      │
│                                    │                                  │
│                                    ▼                                  │
│  ┌────────────────────────────────────────────────────────────┐      │
│  │ Secrets Store CSI Driver Pod                               │      │
│  │  - Polls AWS Secrets Manager every 2 minutes               │      │
│  │  - Authenticates using IRSA (ServiceAccount)               │      │
│  │  - Fetches secrets defined in SecretProviderClass          │      │
│  │  - Mounts secrets as files                                 │      │
│  │  - Syncs to Kubernetes Secret                              │      │
│  └────────────────────────────────────────────────────────────┘      │
│                          │                   │                        │
│                          ▼                   ▼                        │
│  ┌─────────────────────────┐    ┌────────────────────────────┐       │
│  │ CSI Volume Mount        │    │ Kubernetes Secret          │       │
│  │ /mnt/secrets/           │    │ service-a-secrets          │       │
│  │  ├─ database-url        │    │                            │       │
│  │  ├─ database-username   │    │ DATA:                      │       │
│  │  └─ database-password   │    │  DATABASE_URL: <base64>    │       │
│  └─────────────────────────┘    │  DATABASE_USERNAME: <b64>  │       │
│              │                  │  DATABASE_PASSWORD: <b64>  │       │
│              │                  └────────────────────────────┘       │
│              │                              │                        │
│              │                              │ Reloader watches       │
│              │                              │ this Secret            │
│              ▼                              ▼                        │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │ Service A Pod                                             │       │
│  │                                                           │       │
│  │  ServiceAccount: service-a                                │       │
│  │  (eks.amazonaws.com/role-arn: arn:aws:iam::...)          │       │
│  │                                                           │       │
│  │  Volumes:                                                 │       │
│  │    - name: secrets-store                                  │       │
│  │      csi:                                                 │       │
│  │        driver: secrets-store.csi.k8s.io                   │       │
│  │        volumeAttributes:                                  │       │
│  │          secretProviderClass: service-a-secrets           │       │
│  │                                                           │       │
│  │  Container:                                               │       │
│  │    volumeMounts:                                          │       │
│  │      - mountPath: /mnt/secrets                            │       │
│  │    envFrom:                                               │       │
│  │      - secretRef:                                         │       │
│  │          name: service-a-secrets                          │       │
│  │                                                           │       │
│  │  Application can read secrets via:                        │       │
│  │    1. Files: cat /mnt/secrets/database-password           │       │
│  │    2. Env vars: echo $DATABASE_PASSWORD                   │       │
│  └──────────────────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────────────────┘

WHEN SECRET CHANGES:
1. Engineer updates secret in AWS Secrets Manager
2. CSI Driver detects change (next poll, max 2 min)
3. CSI Driver updates mounted files in /mnt/secrets/
4. CSI Driver updates Kubernetes Secret
5. Reloader detects Secret change (watches annotation)
6. Reloader triggers rolling restart of Deployment
7. New pods start with updated secrets
```

---

## 5. Helm Chart Templating Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   HELM CHART STRUCTURE                           │
│                                                                  │
│  charts/vsf-miniapp/                                             │
│    ├── Chart.yaml                                                │
│    ├── values.yaml          ◀── Common defaults for all services│
│    ├── templates/                                                │
│    │   ├── _helpers.tpl     ◀── Helper functions                │
│    │   ├── deployment.yaml  ◀── Parameterized template          │
│    │   ├── service.yaml                                          │
│    │   ├── ...                                                   │
│    └── ci/                  ◀── Service-specific overrides       │
│        ├── service-a-production.yaml                             │
│        ├── service-b-production.yaml                             │
│        └── service-c-production.yaml                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                │ ArgoCD invokes Helm
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  HELM RENDERING PROCESS                                          │
│                                                                  │
│  Step 1: Load values.yaml (defaults)                             │
│    serviceName: "default-service"                                │
│    replicaCount: 3                                               │
│    image:                                                        │
│      repository: YOUR_ECR/default                                │
│      tag: latest                                                 │
│                                                                  │
│  Step 2: Merge service-a-production.yaml                         │
│    serviceName: "service-a"  ◀── Override                        │
│    replicaCount: 5           ◀── Override                        │
│    image:                                                        │
│      repository: YOUR_ECR/vsf-miniapp-service-a  ◀── Override    │
│      tag: "1.0.0"            ◀── Override                        │
│    service:                                                      │
│      targetPort: 8080        ◀── Java-specific                   │
│    env:                                                          │
│      - name: JAVA_OPTS       ◀── Java-specific                   │
│        value: "-Xmx768m"                                         │
│                                                                  │
│  Step 3: Render templates                                        │
│    templates/deployment.yaml:                                    │
│      name: {{ .Values.serviceName }}  → name: service-a          │
│      replicas: {{ .Values.replicaCount }}  → replicas: 5         │
│      image: {{ .Values.image.repository }}:{{ .Values.image.tag }}│
│        → image: YOUR_ECR/vsf-miniapp-service-a:1.0.0             │
│                                                                  │
│  Step 4: Output final Kubernetes YAML                            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  RENDERED KUBERNETES MANIFESTS                                   │
│                                                                  │
│  apiVersion: apps/v1                                             │
│  kind: Deployment                                                │
│  metadata:                                                       │
│    name: service-a                                               │
│    labels:                                                       │
│      service: service-a                                          │
│      language: java                                              │
│  spec:                                                           │
│    replicas: 5                                                   │
│    template:                                                     │
│      metadata:                                                   │
│        annotations:                                              │
│          linkerd.io/inject: enabled  ◀── Linkerd mTLS enabled    │
│          reloader.stakater.com/auto: "true"  ◀── Auto-reload     │
│      spec:                                                       │
│        serviceAccountName: service-a  ◀── IRSA for secrets       │
│        containers:                                               │
│          - name: service-a                                       │
│            image: YOUR_ECR/vsf-miniapp-service-a:1.0.0           │
│            ports:                                                │
│              - containerPort: 8080                               │
│            env:                                                  │
│              - name: JAVA_OPTS                                   │
│                value: "-Xmx768m"                                 │
│            envFrom:                                              │
│              - secretRef:                                        │
│                  name: service-a-secrets  ◀── From AWS Secrets   │
│            volumeMounts:                                         │
│              - name: secrets-store                               │
│                mountPath: /mnt/secrets                           │
│        volumes:                                                  │
│          - name: secrets-store                                   │
│            csi:                                                  │
│              driver: secrets-store.csi.k8s.io                    │
│              volumeAttributes:                                   │
│                secretProviderClass: service-a-secrets            │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                       Applied to Kubernetes Cluster
```

---

## 6. Deployment Timeline

```
Time: 0s                Developer pushes code to main branch
      │
      ├─▶ GitHub Actions CI triggers
      │
Time: 30s               CI completes build and tests
      │
      ├─▶ Docker image built and pushed to ECR
      │   Image: YOUR_ECR/vsf-miniapp-service-a:1.2.3
      │
Time: 60s               CI updates Git repository
      │
      ├─▶ charts/vsf-miniapp/ci/service-a-production.yaml
      │   image.tag: "1.2.3"
      │
      ├─▶ Git commit and push
      │
Time: 90s               ArgoCD detects Git change (polling interval)
      │
      ├─▶ ArgoCD syncs application
      │
Time: 120s              Kubernetes rolling update begins
      │
      ├─▶ New pod created (service-a-new)
      │   ├─ Linkerd proxy injected automatically
      │   ├─ CSI driver mounts secrets from AWS
      │   └─ Container starts
      │
Time: 150s              New pod passes readiness probe
      │
      ├─▶ Service starts routing traffic to new pod
      │
Time: 180s              Old pod terminated gracefully
      │
      └─▶ Deployment complete

Total deployment time: ~3 minutes from code push to production
```

---

## Summary

This architecture provides:

✅ **Zero-trust security** - Linkerd mTLS for all service communication
✅ **Secret management** - AWS Secrets Manager with automatic rotation
✅ **GitOps deployment** - ArgoCD syncs from Git
✅ **Multi-language support** - Java, Node.js, Python via shared chart
✅ **High availability** - HPA, PDB, multi-AZ deployment
✅ **Observability** - Prometheus metrics, Linkerd Viz
✅ **Automated operations** - Reloader watches config changes
✅ **Infrastructure as Code** - Everything in Git

The platform is **production-ready** and follows **cloud-native best practices**.
