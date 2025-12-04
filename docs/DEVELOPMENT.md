# Development Guide

## Adding a New Service

To add **Service C** (e.g., Python):

1.  **Create Values File:**
    Copy `charts/vsf-miniapp/ci/service-b-production.yaml` to `service-c-production.yaml`.
    ```yaml
    serviceName: service-c
    language: python
    image: { repository: "...", tag: "..." }
    service: { targetPort: 8000 }
    ```

2.  **Create Application Manifest:**
    Copy `applications/applicationsets/services.yaml` logic (it's automatic!)
    *Actually, just update `applications/applicationsets/services.yaml` to include `service-c` in the list generator.*

    ```yaml
    - list:
        elements:
          - service: service-a
          - service: service-b
          - service: service-c  # <--- Add this
    ```

3.  **Create Secrets:**
    Create `production/vsf-miniapp/service-c/*` in AWS Secrets Manager.

4.  **Deploy:**
    Commit and push. ArgoCD ApplicationSet will automatically create the new apps.

---

## 🔄 CI/CD Pipeline

The CI pipeline (`.github/workflows/ci-build-deploy.yaml`) automates the delivery process:

1.  **Lint**: Validates Helm charts with environment values.
2.  **Validate**: Checks manifests with kubeval.
3.  **Build**: Creates Docker image.
4.  **Push**: Uploads image to ECR.
5.  **Package**: Packages Helm chart and pushes to OCI registry.
6.  **Update**: Commits new image tag to Git.
7.  **Sync**: Triggers ArgoCD (automatic via Git polling).

---

## 🏆 Best Practices

### 1. Never `kubectl apply` Manually
Always commit changes to Git and let ArgoCD sync.
*   ❌ `kubectl apply -f deployment.yaml`
*   ✅ `git commit -m "update replicas" && git push`

### 2. Semantic Versioning
Tag your releases properly to ensure traceability.
```bash
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

### 3. Environment Promotion
Promote changes through environments using Git branches.
1.  **Dev**: Push to `develop` branch.
2.  **Prod**: Merge `develop` to `main`.

### 4. Security First
*   **Never commit secrets to Git.** Use AWS Secrets Manager.
*   **Least Privilege:** Use specific IAM roles (IRSA) for each service.
*   **Read-Only:** Run containers with read-only root filesystems where possible.

---

## Helm + Kustomize Patterns

We use a **Hybrid Pattern** for infrastructure:

-   **Helm:** Used for upstream charts (Traefik, Linkerd). Defined in ArgoCD Source 1.
-   **Kustomize:** Used for local overlays (ConfigMaps, middlewares). Defined in ArgoCD Source 2.

**Avoid:** "Helm Inflation" in Kustomize (using `helmCharts` field in kustomization.yaml). It causes TLS issues.

### Project Structure
-   `charts/`: Shared Helm charts for *Apps*.
-   `infrastructure/`: Kustomize overlays for *Infra*.
-   `applications/`: ArgoCD manifests.