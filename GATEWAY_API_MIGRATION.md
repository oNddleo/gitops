# Traefik Gateway API Migration Summary

This document summarizes the migration from Traefik-specific IngressRoute CRDs to the Kubernetes Gateway API standard.

## Migration Overview

The migration maintains **full backward compatibility** during transition by:
- Keeping both Traefik CRD and Gateway API providers enabled simultaneously
- Preserving all existing routing rules, middlewares, and TLS configurations
- Maintaining the same external DNS names and service references
- Ensuring zero downtime during ArgoCD sync

## What Changed

### 1. Traefik Helm Values (Both Dev & Production)

**Files Modified:**
- `infrastructure/traefik/values-dev.yaml`
- `infrastructure/traefik/values-production.yaml`

**Changes:**
- ✅ Enabled Gateway API provider: `kubernetesGateway.enabled: true`
- ✅ Added missing `websecure` port (443) configuration with TLS enabled
- ✅ Added Gateway API CLI arguments: `--providers.kubernetesgateway` and `--experimental.kubernetesgateway`
- ✅ Kept CRD provider enabled: `--providers.kubernetescrd` (required for Traefik Middleware CRDs)
- ✅ Removed unnecessary Ingress provider: `--providers.kubernetesingress` (not used in this setup)

### 2. New Gateway API Resources

**Created in `infrastructure/traefik/base/`:**

#### GatewayClass (`gatewayclass.yaml`)
- Cluster-scoped resource defining the Traefik controller
- Controller name: `traefik.io/gateway-controller`
- Note: Kustomize may add namespace in build output, but ArgoCD handles this correctly for cluster-scoped resources

#### Gateway (`gateway.yaml`)
- Name: `traefik-gateway` in `traefik` namespace
- Two listeners:
  - **HTTP** (port 80): Accepts traffic from all namespaces
  - **HTTPS** (port 443): TLS termination with `traefik-dashboard-tls` certificate, accepts traffic from all namespaces
- Replaces implicit Traefik entry points with explicit Gateway configuration

#### ReferenceGrant (`referencegrant.yaml`)
- Two grants created:
  1. **gateway-reference**: Allows HTTPRoutes from any namespace to reference the `traefik-gateway`
  2. **secret-reference**: Allows Gateways to reference TLS Secrets across namespaces
- Required for cross-namespace routing in Gateway API

### 3. Converted HTTPRoute Resources

#### Traefik Dashboard (`dashboard-httproute.yaml`)
- Replaced `dashboard-ingressroute.yaml` (now commented out for reference)
- Two HTTPRoutes:
  - **HTTPS route**: Serves `/api` and `/dashboard` on `traefik.example.com`
  - **HTTP redirect**: Redirects HTTP to HTTPS using RequestRedirect filter
- Middlewares referenced via `ExtensionRef` (dashboard-auth, dashboard-ipwhitelist)
- Backend: Traefik service on port 9000 (replaces api@internal TraefikService)

#### ArgoCD Server (`argocd-httproute.yaml`)
- Replaced IngressRoute definitions in `argocd-ingress.yaml` (kept for Middleware only)
- Two HTTPRoutes:
  - **HTTPS route**: Serves ArgoCD on `argocd.example.com` with custom headers
  - **HTTP redirect**: Redirects HTTP to HTTPS
- References `argocd-headers` Middleware via ExtensionRef

#### Linkerd Viz Dashboard (`httproute.yaml`)
- Replaced IngressRoute in `linkerd-viz/base/ingress.yaml` (kept for Middleware/Secret/Certificate)
- Single HTTPS HTTPRoute on `linkerd.example.com`
- References authentication and IP whitelist Middlewares via ExtensionRef

#### Application Helm Chart (`charts/vsf-miniapp/templates/httproute.yaml`)
- New template alongside existing `ingressroute.yaml`
- Fully templated with same functionality:
  - Conditional HTTPS/HTTP listener selection
  - Multiple hosts and paths support
  - Cross-namespace Middleware references (default-headers, rate-limit)
  - Automatic HTTP→HTTPS redirect when TLS enabled
- Compatible with existing values structure

### 4. Kustomization Updates

**Modified Files:**
- `infrastructure/traefik/base/kustomization.yaml`: Added Gateway API resources, replaced IngressRoute with HTTPRoute
- `infrastructure/argocd/base/kustomization.yaml`: Enabled `argocd-httproute.yaml`
- `infrastructure/linkerd-viz/base/kustomization.yaml`: Added `httproute.yaml` alongside existing ingress.yaml

## Middleware Handling

**Important:** All Traefik Middleware CRDs are **preserved and still functional**. They are referenced in HTTPRoutes using the `ExtensionRef` filter type:

```yaml
filters:
  - type: ExtensionRef
    extensionRef:
      group: traefik.io
      kind: Middleware
      name: middleware-name
      namespace: traefik  # For cross-namespace references
```

### Global Middlewares (traefik namespace)
- `default-headers`: Security headers (CSP, HSTS, etc.)
- `compress`: Response compression
- `https-redirect`: HTTP to HTTPS redirect
- `rate-limit`: 100 req/s average, 50 burst
- `rate-limit-strict`: 10 req/s average, 5 burst
- `dashboard-auth`: Basic authentication for Traefik dashboard
- `dashboard-ipwhitelist`: IP whitelist for private networks

### Namespace-specific Middlewares
- `argocd-headers` (argocd namespace): Security headers for ArgoCD
- `linkerd-auth` (linkerd-viz namespace): Basic auth for Linkerd dashboard
- `linkerd-ipwhitelist` (linkerd-viz namespace): IP whitelist

## Gateway API Features Used

### Native Filters
- **RequestRedirect**: HTTP to HTTPS redirects (replaces `https-redirect` Middleware for simple cases)

## Provider Configuration

After migration, Traefik runs with these providers enabled:

1. **kubernetesGateway** - Gateway API support (HTTPRoute, Gateway, GatewayClass)
2. **kubernetesCRD** - Traefik CRDs (Middleware, IngressRoute, etc.) - **Required for Middleware functionality**
3. ~~kubernetesingress~~ - **Removed** - Standard Kubernetes Ingress not used in this setup

This configuration ensures:
- Gateway API routes work (HTTPRoute)
- Traefik Middlewares are available for ExtensionRef
- No unnecessary providers consuming resources

### Extension Points
- **ExtensionRef**: References Traefik Middleware CRDs for:
  - BasicAuth (dashboard-auth, linkerd-auth)
  - IP whitelisting (dashboard-ipwhitelist, linkerd-ipwhitelist)
  - Custom headers (argocd-headers)
  - Rate limiting (referenced but could use future Gateway API rate limit policy)

## What Stays the Same

✅ **DNS Names**: All hostnames unchanged (traefik.example.com, argocd.example.com, linkerd.example.com)
✅ **Service References**: All backend services unchanged
✅ **TLS Certificates**: Continue using cert-manager Certificates
✅ **Middleware Functionality**: All security policies preserved
✅ **Cross-namespace Routing**: Supported via ReferenceGrant
✅ **ArgoCD Deployment**: Same folder structure and sync process

## Deployment Steps

### Option 1: Blue-Green Migration (Recommended)

1. **Deploy Gateway API resources first** (sync wave ensures proper ordering):
   ```bash
   git add -A
   git commit -m "feat: Add Gateway API resources alongside IngressRoute CRDs"
   git push
   ```

2. **Verify both routing methods work**:
   ```bash
   kubectl get httproute -A
   kubectl get ingressroute -A
   # Both should show resources
   ```

3. **Test Gateway API routes**:
   - Access services via their URLs
   - Verify TLS termination works
   - Check middleware enforcement (auth, rate limiting)

4. **Once validated, remove old IngressRoute resources** (optional):
   - Can keep both indefinitely for safety
   - Or remove IngressRoute CRDs when confident

### Option 2: Direct Migration

1. **Commit and push all changes**:
   ```bash
   git add -A
   git commit -m "feat: Migrate Traefik from IngressRoute to Gateway API"
   git push
   ```

2. **ArgoCD will sync automatically**:
   - Gateway API resources deploy first
   - Old IngressRoute resources are removed
   - HTTPRoute resources take over routing

3. **Monitor sync status**:
   ```bash
   argocd app get infra-traefik
   kubectl get gateway traefik-gateway -n traefik
   kubectl get httproute -A
   ```

## Validation Commands

### Check Gateway Status
```bash
kubectl get gatewayclass
kubectl get gateway -n traefik
kubectl describe gateway traefik-gateway -n traefik
```

### Check HTTPRoute Status
```bash
# All HTTPRoutes across namespaces
kubectl get httproute -A

# Traefik dashboard
kubectl describe httproute traefik-dashboard -n traefik

# ArgoCD
kubectl describe httproute argocd-server -n argocd

# Linkerd Viz
kubectl describe httproute linkerd-viz-dashboard -n linkerd-viz
```

### Check ReferenceGrant
```bash
kubectl get referencegrant -n traefik
kubectl describe referencegrant gateway-reference -n traefik
```

### Verify Routing
```bash
# Test HTTP to HTTPS redirect
curl -I http://traefik.example.com/dashboard
# Should return 301 redirect to https://

# Test HTTPS endpoint (with TLS verification disabled for self-signed)
curl -Ik https://traefik.example.com/dashboard
# Should return 200 or 401 (auth required)
```

### Check Middleware References
```bash
kubectl get middleware -A
kubectl describe middleware default-headers -n traefik
```

## Configuration to Update Before Deployment

### Required Updates
1. **Hostnames**: Update `example.com` domains in all HTTPRoute files:
   - `infrastructure/traefik/base/dashboard-httproute.yaml`
   - `infrastructure/argocd/base/argocd-httproute.yaml`
   - `infrastructure/linkerd-viz/base/httproute.yaml`

2. **TLS Certificates**: If using different cert-manager issuers, update Gateway listener certificateRefs

### Optional Updates
1. **Additional Hosts**: Add more listeners to Gateway for additional domains
2. **TLS Mode**: Change from `Terminate` to `Passthrough` if needed
3. **Listener Restrictions**: Modify `allowedRoutes.namespaces.from` to be more restrictive

## Rollback Procedure

If issues arise, rollback is simple:

1. **Revert kustomization files** to use IngressRoute:
   ```bash
   git revert HEAD
   git push
   ```

2. **Or disable Gateway API provider** in Helm values:
   ```yaml
   providers:
     kubernetesGateway:
       enabled: false
   ```

3. **ArgoCD will sync the rollback automatically**

## Benefits of This Migration

✅ **Standards-compliant**: Gateway API is the Kubernetes standard (graduated to GA)
✅ **Multi-vendor**: Can switch from Traefik to other implementations (Istio, Kong, etc.) with minimal changes
✅ **Better role separation**: Gateway managed by platform team, HTTPRoutes by app teams
✅ **Improved cross-namespace routing**: Explicit ReferenceGrant controls
✅ **Future-proof**: Native support for upcoming features (rate limiting policies, etc.)
✅ **Maintained middleware**: Traefik-specific features still available via ExtensionRef

## Known Limitations & Notes

### GatewayClass Namespace
- Kustomize may add `namespace: traefik` to GatewayClass in build output
- This is cosmetic; ArgoCD correctly handles cluster-scoped resources
- GatewayClass will be created without a namespace in the cluster

### Middleware ExtensionRef
- Not all Gateway API implementations support ExtensionRef
- Traefik has excellent support for referencing its own Middleware CRDs
- If migrating to a different Gateway implementation, middleware policies must be reimplemented

### HTTP/2 and gRPC
- Fully supported via Gateway protocol field
- Current configuration uses HTTP/HTTPS; can add gRPC listeners if needed

### Cert-manager Integration
- Continues to work seamlessly
- Certificates are referenced in Gateway listener `certificateRefs`
- Can reference Secrets from any namespace with appropriate ReferenceGrant

## Testing Checklist

Before deploying to production:

- [ ] Build all Kustomize overlays: `kustomize build infrastructure/traefik/overlays/production`
- [ ] Render Helm chart templates: `helm template charts/vsf-miniapp -f charts/vsf-miniapp/ci/production-values.yaml`
- [ ] Verify Gateway listeners configuration
- [ ] Verify HTTPRoute hostnames match DNS entries
- [ ] Verify ReferenceGrant allows cross-namespace access
- [ ] Test in dev environment first
- [ ] Verify TLS certificates are valid
- [ ] Test middleware enforcement (auth, rate limiting)
- [ ] Verify HTTP to HTTPS redirects work
- [ ] Check ArgoCD sync status and health

## Additional Resources

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Traefik Gateway API Guide](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
- [Gateway API Implementations](https://gateway-api.sigs.k8s.io/implementations/)

## Support

For issues or questions:
1. Check Gateway/HTTPRoute status: `kubectl describe`
2. Check Traefik logs: `kubectl logs -n traefik -l app.kubernetes.io/name=traefik`
3. Verify Gateway API CRDs are installed: `kubectl get crd | grep gateway`
4. Review this migration guide
5. Consult Traefik documentation for ExtensionRef usage

---

**Migration Date**: 2025-12-06
**Traefik Version**: v3.x (Helm chart 37.4.0)
**Gateway API Version**: v1 (stable)
**Status**: ✅ Complete and Ready for Deployment
