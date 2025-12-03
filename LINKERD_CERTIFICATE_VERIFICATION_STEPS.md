# Linkerd Certificate Verification Steps

## Quick Reference - Verify Certificate Matching

When you encounter errors like:
- `Failed to load trust anchors: 'LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS' must be set`
- `failed to verify issuer credentials: x509: certificate signed by unknown authority`

Follow these steps to verify and fix certificate mismatches.

---

## Step 1: Extract Certificates from Cluster

### 1.1 Get Trust Anchor Certificate
```bash
kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/trust-anchor.crt
```

### 1.2 Get Issuer Certificate
```bash
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/issuer.crt
```

### 1.3 Get Trust Roots from ConfigMap
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/ca-bundle.crt
```

---

## Step 2: Verify Certificate Chain

### 2.1 Check Issuer Certificate Issuer
```bash
openssl x509 -in /tmp/issuer.crt -noout -issuer
```

**Expected Output:**
```
issuer=CN = root.linkerd.cluster.local
```

### 2.2 Check Trust Anchor Subject
```bash
openssl x509 -in /tmp/trust-anchor.crt -noout -subject
```

**Expected Output:**
```
subject=CN = root.linkerd.cluster.local
```

### 2.3 **CRITICAL**: Verify Issuer Against Trust Anchor
```bash
openssl verify -CAfile /tmp/trust-anchor.crt /tmp/issuer.crt
```

**Expected Output:**
```
/tmp/issuer.crt: OK
```

**If you see this error:**
```
error 20 at 0 depth lookup: unable to get local issuer certificate
error /tmp/issuer.crt: verification failed
```
**This means the certificates DON'T MATCH!** The issuer was signed by a different CA.

### 2.4 Verify ConfigMap Certificate Matches Trust Anchor
```bash
openssl verify -CAfile /tmp/ca-bundle.crt /tmp/issuer.crt
```

**Expected:** Should also return `OK`

---

## Step 3: Compare Certificate Fingerprints

### 3.1 Get Trust Anchor Fingerprint
```bash
openssl x509 -in /tmp/trust-anchor.crt -noout -fingerprint -sha256
```

### 3.2 Get ConfigMap CA Bundle Fingerprint
```bash
openssl x509 -in /tmp/ca-bundle.crt -noout -fingerprint -sha256
```

### 3.3 Compare
**These fingerprints MUST match!** If they don't, the ConfigMap has the wrong certificate.

---

## Step 4: Check Certificate Files in Repository

### 4.1 Verify Generated Certificates Exist
```bash
ls -la infrastructure/linkerd/base/certs/
```

**Expected files:**
```
ca.crt       # Trust anchor certificate
ca.key       # Trust anchor private key
issuer.crt   # Issuer certificate
issuer.key   # Issuer private key
```

### 4.2 Verify Generated Certificates Match
```bash
openssl verify -CAfile infrastructure/linkerd/base/certs/ca.crt \
  infrastructure/linkerd/base/certs/issuer.crt
```

**Expected:** `/tmp/issuer.crt: OK`

### 4.3 Get Fingerprints of Generated Certificates
```bash
echo "Generated CA fingerprint:"
openssl x509 -in infrastructure/linkerd/base/certs/ca.crt -noout -fingerprint -sha256

echo "Cluster trust anchor fingerprint:"
openssl x509 -in /tmp/trust-anchor.crt -noout -fingerprint -sha256
```

**Compare these** - they should either:
- **Match**: Use the generated certs everywhere
- **Not match**: You have two different CA certificates, pick one set and use it consistently

---

## Step 5: Check Helm Values in ArgoCD

### 5.1 Check What Certificate is in Helm Values
```bash
kubectl get application linkerd-control-plane -n argocd -o yaml | \
  grep -A 35 "identityTrustAnchorsPEM:"
```

### 5.2 Extract the Certificate from Helm Values
```bash
kubectl get application linkerd-control-plane -n argocd -o yaml | \
  sed -n '/identityTrustAnchorsPEM:/,/-----END CERTIFICATE-----/p' | \
  sed '1d' | sed 's/^[[:space:]]*//' > /tmp/helm-ca.crt
```

### 5.3 Get Fingerprint of Helm Values Certificate
```bash
openssl x509 -in /tmp/helm-ca.crt -noout -fingerprint -sha256
```

### 5.4 Verify it Matches Issuer
```bash
openssl verify -CAfile /tmp/helm-ca.crt /tmp/issuer.crt
```

**Expected:** `OK`

**If verification fails**, the certificate in Helm values doesn't match the issuer secret!

---

## Step 6: Fix Certificate Mismatch

### Option A: Update Secrets to Match Generated Certificates

If you want to use the newly generated certificates from `infrastructure/linkerd/base/certs/`:

```bash
# Update issuer secret
kubectl create secret tls linkerd-identity-issuer \
  --cert=infrastructure/linkerd/base/certs/issuer.crt \
  --key=infrastructure/linkerd/base/certs/issuer.key \
  --namespace=linkerd \
  --dry-run=client -o yaml | kubectl apply -f -

# Label the secret
kubectl label secret linkerd-identity-issuer \
  linkerd.io/control-plane-component=identity \
  linkerd.io/control-plane-ns=linkerd \
  -n linkerd --overwrite

# Update trust anchor (note: can't change type, so delete first if needed)
kubectl delete secret linkerd-trust-anchor -n linkerd
kubectl create secret generic linkerd-trust-anchor \
  --from-file=tls.crt=infrastructure/linkerd/base/certs/ca.crt \
  --from-file=tls.key=infrastructure/linkerd/base/certs/ca.key \
  --namespace=linkerd

kubectl label secret linkerd-trust-anchor \
  linkerd.io/control-plane-component=identity \
  linkerd.io/control-plane-ns=linkerd \
  -n linkerd --overwrite
```

### Option B: Update Helm Values to Match Cluster Secrets

If you want to keep using the certificates already in the cluster:

1. **Extract the correct CA from cluster:**
```bash
kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.tls\.crt}' | \
  base64 -d > correct-ca.crt
```

2. **Update `applications/infrastructure/linkerd-control-plane.yaml`:**
Replace the `identityTrustAnchorsPEM` section with the contents of `correct-ca.crt`

3. **Verify it matches the issuer:**
```bash
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | \
  base64 -d > issuer.crt

openssl verify -CAfile correct-ca.crt issuer.crt
```

Should return: `issuer.crt: OK`

---

## Step 7: Apply and Verify Fix

### 7.1 Commit and Push Changes
```bash
git add applications/infrastructure/linkerd-control-plane.yaml
git commit -m "fix: update Linkerd trust anchor certificate to match issuer"
git push
```

### 7.2 Force ArgoCD Refresh
```bash
# Delete ConfigMap to force recreation
kubectl delete configmap linkerd-identity-trust-roots -n linkerd

# Trigger ArgoCD refresh
kubectl patch application linkerd-control-plane -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### 7.3 Wait for ConfigMap Regeneration
```bash
sleep 10
kubectl get configmap linkerd-identity-trust-roots -n linkerd
```

### 7.4 Verify New ConfigMap Matches
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/new-ca-bundle.crt

openssl verify -CAfile /tmp/new-ca-bundle.crt /tmp/issuer.crt
```

**Expected:** `/tmp/issuer.crt: OK`

### 7.5 Delete Pods to Force Restart
```bash
kubectl delete pods --all -n linkerd
```

### 7.6 Monitor Pod Recovery
```bash
watch kubectl get pods -n linkerd
```

**Wait for all pods to reach `Running` status with all containers ready (e.g., `4/4`, `2/2`).**

### 7.7 Check Pod Logs for Errors
```bash
kubectl logs -n linkerd -l linkerd.io/control-plane-component=identity --tail=20
```

**Expected:** No "certificate signed by unknown authority" errors

---

## Common Issues and Solutions

### Issue 1: ConfigMap Still Has Wrong Certificate After Update

**Symptom:**
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' | \
  openssl x509 -noout -fingerprint -sha256
```
Shows different fingerprint than expected.

**Solution:**
1. Delete the ArgoCD Application completely
2. Reapply it from the file

```bash
kubectl delete application linkerd-control-plane -n argocd
sleep 5
kubectl apply -f applications/infrastructure/linkerd-control-plane.yaml
```

### Issue 2: Pods Still Crashing After Certificate Fix

**Check:**
1. Verify ConfigMap has correct certificate:
```bash
kubectl describe configmap linkerd-identity-trust-roots -n linkerd
```

2. Check if pods are using old cached config:
```bash
kubectl delete pods --all -n linkerd
```

3. Check for other errors:
```bash
kubectl logs -n linkerd <pod-name> -c linkerd-proxy --tail=50
kubectl logs -n linkerd <pod-name> -c identity --tail=50
```

### Issue 3: Multiple Certificate Sets Causing Confusion

**Symptom:** You have certificates in multiple places and don't know which to use.

**Solution - Audit All Certificates:**

```bash
echo "=== Cluster Trust Anchor ==="
kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -fingerprint -sha256

echo "=== Cluster Issuer ==="
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -fingerprint -sha256

echo "=== ConfigMap CA Bundle ==="
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' | \
  openssl x509 -noout -fingerprint -sha256

echo "=== Generated CA (in repo) ==="
openssl x509 -in infrastructure/linkerd/base/certs/ca.crt -noout -fingerprint -sha256

echo "=== Generated Issuer (in repo) ==="
openssl x509 -in infrastructure/linkerd/base/certs/issuer.crt -noout -fingerprint -sha256

echo "=== Helm Values CA (in ArgoCD) ==="
kubectl get application linkerd-control-plane -n argocd -o yaml | \
  sed -n '/identityTrustAnchorsPEM:/,/-----END CERTIFICATE-----/p' | \
  sed '1d' | sed 's/^[[:space:]]*//' | \
  openssl x509 -noout -fingerprint -sha256
```

**Pick ONE certificate set** where:
- CA fingerprint matches between trust anchor secret, ConfigMap, and Helm values
- Issuer was signed by that CA (verify with `openssl verify`)

Then update all locations to use that consistent set.

---

## Quick Verification Checklist

Use this checklist to verify certificates are configured correctly:

- [ ] Trust anchor secret exists: `kubectl get secret linkerd-trust-anchor -n linkerd`
- [ ] Issuer secret exists: `kubectl get secret linkerd-identity-issuer -n linkerd`
- [ ] ConfigMap exists and has certificate: `kubectl get configmap linkerd-identity-trust-roots -n linkerd`
- [ ] Issuer verifies against trust anchor: `openssl verify -CAfile <trust-anchor> <issuer>` returns `OK`
- [ ] ConfigMap certificate matches trust anchor fingerprint
- [ ] Helm values `identityTrustAnchorsPEM` matches trust anchor fingerprint
- [ ] All Linkerd pods are Running: `kubectl get pods -n linkerd`
- [ ] No certificate errors in logs: `kubectl logs -n linkerd -l linkerd.io/control-plane-component=identity`

---

## Summary

**The Golden Rule**: The issuer certificate MUST be signed by the trust anchor certificate. All three places must have the SAME trust anchor:
1. `linkerd-trust-anchor` secret
2. `linkerd-identity-trust-roots` ConfigMap (`ca-bundle.crt` key)
3. ArgoCD Application Helm values (`identityTrustAnchorsPEM`)

**Verification Command:**
```bash
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/issuer.crt
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/ca.crt
openssl verify -CAfile /tmp/ca.crt /tmp/issuer.crt
```

**Expected Result:** `/tmp/issuer.crt: OK`

If this fails, follow Step 6 to fix the mismatch.
