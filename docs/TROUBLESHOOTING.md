# Troubleshooting Guide

## Linkerd Issues

### Certificate Verification
If you see `x509: certificate signed by unknown authority` or pods crashing:

1.  **Verify Trust Anchors:**
    ```bash
    # Get Issuer
    kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d > issuer.crt
    # Get Bundle
    kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' > ca.crt
    # Verify
    openssl verify -CAfile ca.crt issuer.crt
    ```
    *Must return OK.*

2.  **Fix Trust Anchor:**
    If mismatch, update `applications/infrastructure/linkerd-control-plane.yaml` with the correct certificate in `identityTrustAnchorsPEM`.

### mTLS Not Working
1.  Check injection: `kubectl get pod -o yaml | grep linkerd.io/inject`.
2.  Restart deployment: `kubectl rollout restart deploy <name>`.

---

## Application Issues

### Secrets Not Mounting
1.  **Check Provider Class:** `kubectl describe secretproviderclass`.
2.  **Check CSI Driver Logs:** `kubectl logs -n kube-system -l app=secrets-store-csi-driver`.
3.  **Test Access:**
    ```bash
    kubectl run aws-test --rm -it --image=amazon/aws-cli --serviceaccount=<sa-name> -- \
      secretsmanager get-secret-value --secret-id <id>
    ```

### Config Not Reloading
1.  Check annotation: `reloader.stakater.com/auto: "true"`.
2.  Check Reloader logs: `kubectl logs -n reloader -l app=reloader`.

---

## CI/CD Issues

### GitHub Actions Fails
-   **Lint Error:** Check YAML syntax.
-   **Build Error:** Check Dockerfile.
-   **Push Error:** Check AWS Credentials in GitHub Secrets.

### ArgoCD OutOfSync
-   **Diff:** Check what changed.
-   **Hooks:** Check if a hook failed.
-   **Hard Refresh:** `argocd app refresh <app> --hard`.
