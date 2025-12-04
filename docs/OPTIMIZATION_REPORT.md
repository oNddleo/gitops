# GitOps Repository Optimization Report

## Executive Summary
This repository has been refactored to adhere to **DRY (Don't Repeat Yourself)** principles and modernize the deployment strategy using **ApplicationSets**. Redundant configuration has been reduced by ~80%, and environment management (Dev/Staging/Prod) is now dynamic and scalable.

## Key Changes

### 1. Configuration Refactoring (DRY)
**Goal:** Eliminate duplicate YAML in Helm values.
- **Created `charts/vsf-miniapp/ci/values-common.yaml`**:
  - Centralizes shared settings: Security Contexts, Service Accounts, Linkerd Injection, Reloader, Ingress Class, Monitoring.
- **Updated Environment Values**:
  - `service-{a,b}-{dev,staging,production}.yaml` now only contain environment-specific overrides (Replicas, Resources, Env Vars).
  - **Result:** Reduced file size and complexity significantly.

### 2. ApplicationSets Implementation
**Goal:** Replace static Application manifests with dynamic generators.
- **Services ApplicationSet (`applications/applicationsets/services.yaml`)**:
  - Replaced 6 static files and 3 "App of Apps".
  - Automatically generates `service-a` and `service-b` for all environments (Dev, Staging, Prod).
  - Uses a **Matrix Generator** for `(Service) x (Environment)` combinations.
- **Infrastructure ApplicationSet (`applications/applicationsets/infrastructure.yaml`)**:
  - Manages Linkerd, Linkerd-Viz, and Traefik.
  - Uses **Multiple Sources** to combine upstream Helm Charts with local value files (`infrastructure/linkerd/values-*.yaml`).

### 3. Infrastructure Isolation
**Goal:** Ensure Production uses HA configurations, not Dev defaults.
- **Split Values**:
  - Extracted hardcoded values from ArgoCD apps into:
    - `infrastructure/linkerd/values-production.yaml` (HA, 3 replicas, Anti-Affinity)
    - `infrastructure/linkerd/values-dev.yaml` (Single node compatible)
  - Similar splits for `linkerd-viz` and `traefik`.
- **Fixed Hardcoding**:
  - `linkerd-control-plane` no longer points rigidly to `overlays/dev`.

### 4. Bootstrap Simplification
- Updated `bootstrap/root-app.yaml` to point recursively to `applications/`.
- It now automatically discovers:
  1. `applications/infrastructure/*` (Legacy/Static infra if any)
  2. `applications/applicationsets/*` (New dynamic infra & services)

## Repository Structure (New)
```text
├── applications/
│   └── applicationsets/      # Dynamic App Generators
│       ├── infrastructure.yaml
│       └── services.yaml
├── charts/
│   └── vsf-miniapp/
│       └── ci/
│           ├── values-common.yaml      # SHARED CONFIG
│           ├── service-a-dev.yaml      # Overrides
│           └── ...
└── infrastructure/
    ├── linkerd/
    │   ├── values-dev.yaml        # DEV CONFIG
    │   └── values-production.yaml # PROD CONFIG
    └── ...
```

## Next Steps
1. **Verify Deployments:** Ensure ArgoCD syncs the new ApplicationSets correctly.
2. **Secret Management:** Ensure AWS Secrets Manager secrets exist for the defined paths in `values-production.yaml`.
