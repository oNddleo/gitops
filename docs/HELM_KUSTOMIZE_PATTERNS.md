# Helm + Kustomize Patterns Guide

## ✅ Answer: YES, You Can Use Helm + Kustomize!

**But use the HYBRID pattern, not the inflation pattern.**

## 3 Deployment Patterns

### Pattern 1: Pure Helm ⭐ (Simple Components)
**Best for**: Simple infrastructure with minimal customization

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    chart: reloader
    repoURL: https://stakater.github.io/stakater-charts
    targetRevision: 1.0.79
    helm:
      valuesObject:
        # All config here
```

**Examples**: reloader, secrets-store-csi-driver

### Pattern 2: Hybrid Helm + Kustomize ⭐⭐⭐ (RECOMMENDED)
**Best for**: Complex infrastructure with custom resources

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
    # Source 1: Helm chart (direct from registry)
    - repoURL: https://traefik.github.io/charts
      chart: traefik
      targetRevision: 26.0.0
      helm:
        valuesObject:
          # Minimal Helm config

    # Source 2: Kustomize overlay (additional resources)
    - repoURL: https://github.com/oNddleo/gitops.git
      targetRevision: HEAD
      path: infrastructure/traefik-overlay/overlays/dev
```

**Benefits**:
- ✅ Helm chart comes DIRECT from registry (no TLS issues!)
- ✅ Kustomize handles additional resources
- ✅ Easy per-environment customization
- ✅ Clean separation of concerns
- ✅ NO Kustomize Helm inflation problems

**Examples**: traefik-hybrid-example, cert-manager, linkerd

### Pattern 3: Kustomize with Helm Inflation ❌ (AVOID)
**DEPRECATED - Don't use this!**

```yaml
# infrastructure/component/kustomization.yaml
helmCharts:
  - name: chart-name
    repo: https://...
    version: x.y.z
```

**Problems**:
- ❌ TLS certificate verification fails
- ❌ Requires `--enable-helm` flag
- ❌ Complex to debug
- ❌ Kustomize's `helm pull` has issues

## File Structure Examples

### Pattern 1: Pure Helm
```
applications/infrastructure/
└── reloader.yaml           # Single Application manifest

No infrastructure/ directory needed
```

### Pattern 2: Hybrid (RECOMMENDED)
```
infrastructure/
└── traefik-overlay/
    ├── base/
    │   ├── kustomization.yaml
    │   ├── middleware-default-headers.yaml
    │   ├── middleware-rate-limit.yaml
    │   └── ingressroute-dashboard.yaml
    └── overlays/
        ├── dev/
        │   └── kustomization.yaml
        ├── staging/
        │   └── kustomization.yaml
        └── production/
            └── kustomization.yaml

applications/infrastructure/
└── traefik-hybrid.yaml     # Multi-source Application
```

### Pattern 3: Kustomize Inflation (OLD - removed)
```
infrastructure/
└── traefik/
    ├── kustomization.yaml  # Contains helmCharts section
    └── additional-resources.yaml

applications/infrastructure/
└── traefik.yaml            # Points to kustomize path
```

## When to Use What?

### Use Pure Helm (Pattern 1) for:
- Simple components with no custom resources
- Components where Helm values are sufficient
- Quick deployments without environment variations

**Examples**:
- `reloader` - Simple operator
- `secrets-store-csi-driver` - Standard CSI driver
- `external-dns` - Simple controller

### Use Hybrid (Pattern 2) for:
- Components that need custom CRDs beyond Helm chart
- Multi-environment deployments with variations
- Components with middleware, policies, or custom configs

**Examples**:
- `traefik` - Needs Middleware, IngressRoutes
- `cert-manager` - Needs ClusterIssuers, Certificates
- `linkerd` - Needs ServiceProfiles, custom configs
- `istio` - Needs VirtualServices, DestinationRules
- `external-secrets` - Needs SecretStores, ExternalSecrets

## Migration Path

If you have Pattern 3 (Kustomize inflation), migrate to Pattern 2:

### Before (Pattern 3 - Kustomize Inflation):
```yaml
# infrastructure/traefik/kustomization.yaml
helmCharts:
  - name: traefik
    repo: https://traefik.github.io/charts
    version: 26.0.0
    valuesInline:
      # ... all config
resources:
  - middleware.yaml
  - ingressroute.yaml

# applications/infrastructure/traefik.yaml
spec:
  source:
    path: infrastructure/traefik  # Kustomize with Helm
```

### After (Pattern 2 - Hybrid):
```yaml
# infrastructure/traefik-overlay/base/kustomization.yaml
resources:
  - middleware.yaml
  - ingressroute.yaml

# applications/infrastructure/traefik.yaml
spec:
  sources:
    - chart: traefik              # Direct Helm!
      repoURL: https://traefik.github.io/charts
      targetRevision: 26.0.0
      helm:
        valuesObject:
          # ... config
    - repoURL: https://github.com/...
      path: infrastructure/traefik-overlay/base
```

## Testing Your Setup

```bash
# Test Pure Helm application
kubectl get application reloader -n argocd
kubectl get pods -n reloader

# Test Hybrid application
kubectl get application traefik-hybrid-example -n argocd
kubectl get middleware,ingressroute -n traefik

# Check sync status
kubectl get application -n argocd | grep Synced
```

## Troubleshooting

### Issue: "must specify --enable-helm"
**Solution**: You're using Pattern 3 (inflation). Migrate to Pattern 2 (hybrid).

### Issue: TLS certificate verification fails
**Solution**: Register Helm repositories with `insecure: "true"` in ArgoCD.
See: `infrastructure/argocd/helm-repositories.yaml`

### Issue: Kustomize resources not appearing
**Solution**:
1. Ensure path exists in Git
2. Check Application uses `sources` (plural) not `source`
3. Verify both sources are listed

## Summary

| Pattern | Use Case | Complexity | TLS Issues | Flexibility |
|---------|----------|------------|------------|-------------|
| 1. Pure Helm | Simple components | Low | ✅ None | Medium |
| 2. Hybrid | Complex infrastructure | Medium | ✅ None | High |
| 3. Inflation | DEPRECATED | High | ❌ Yes | Medium |

**Recommendation**: Use Pattern 2 (Hybrid) for all infrastructure components that need customization.
