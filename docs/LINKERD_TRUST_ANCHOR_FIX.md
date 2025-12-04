# Linkerd Trust Anchor Certificate Fix - Step by Step Guide

## Problem Summary

**Error:** `Failed to load trust anchors: 'LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS' must be set`

**Root Cause:** The `linkerd-identity-trust-roots` ConfigMap exists but is empty, causing all Linkerd proxy containers to crash in CrashLoopBackOff.

## Prerequisites

- Access to the Kubernetes cluster
- kubectl configured
- Git access to the repository
- Trust anchor certificate already exists in the cluster as a secret

---

## Step 1: Verify the Problem

### 1.1 Check Linkerd Pod Status
```bash
kubectl get pods -n linkerd
```

**Expected Output:** Pods in `CrashLoopBackOff` state:
```
NAME                                      READY   STATUS               RESTARTS
linkerd-destination-845fc7bbfc-k95cm      0/4     CrashLoopBackOff     92
linkerd-identity-67bdb577cc-96prf         0/2     CrashLoopBackOff     34
linkerd-proxy-injector-54497ff5b5-pbrzl   0/2     CrashLoopBackOff     43
```

### 1.2 Check Pod Logs
```bash
kubectl logs -n linkerd -l linkerd.io/control-plane-component=destination --tail=20
```

**Expected Output:**
```
time="2025-12-03T10:43:25Z" level=fatal msg="Failed to load trust anchors: 'LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS' must be set"
```

### 1.3 Check ConfigMap Status
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o yaml
```

**Expected Output:** ConfigMap exists but `ca-bundle.crt` is empty:
```yaml
data:
  ca-bundle.crt: ""
```

### 1.4 Verify Trust Anchor Secret Exists
```bash
kubectl get secret linkerd-trust-anchor -n linkerd
```

**Expected Output:**
```
NAME                   TYPE                DATA   AGE
linkerd-trust-anchor   kubernetes.io/tls   2      176m
```

---

## Step 2: Extract Trust Anchor Certificate

### 2.1 Get the Certificate from Secret
```bash
kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d
```

**Save this output** - you'll need it in Step 3.

**Expected Output:**
```
-----BEGIN CERTIFICATE-----
MIIFKzCCAxOgAwIBAgIUdSfx1cX8ECiH1mX84tkZFsZxTqswDQYJKoZIhvcNAQEL
...
-----END CERTIFICATE-----
```

### 2.2 Verify Certificate is Valid
```bash
kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep -A 2 "Subject:"
```

**Expected Output:**
```
Subject: CN = root.linkerd.cluster.local
```

---

## Step 3: Update Linkerd Control Plane Configuration

### 3.1 Open the ArgoCD Application File
```bash
cd /home/vsf-longnd56-l/Documents/oNddleo/gitops
vi applications/infrastructure/linkerd-control-plane.yaml
```

### 3.2 Locate the valuesObject Section

Find this section (around line 17):
```yaml
valuesObject:
  identity:
    issuer:
      scheme: kubernetes.io/tls
  controllerReplicas: 1
```

### 3.3 Add identityTrustAnchorsPEM Parameter

**Add the certificate BEFORE the `identity:` section:**

```yaml
valuesObject:
  identityTrustAnchorsPEM: |
    -----BEGIN CERTIFICATE-----
    [PASTE YOUR CERTIFICATE FROM STEP 2.1 HERE]
    -----END CERTIFICATE-----
  identity:
    issuer:
      scheme: kubernetes.io/tls
  controllerReplicas: 1
```

**Important Notes:**
- Maintain proper YAML indentation (2 spaces)
- Include the full certificate with BEGIN and END lines
- The `|` character preserves line breaks

### 3.4 Verify the File Syntax
```bash
cat applications/infrastructure/linkerd-control-plane.yaml | grep -A 35 "valuesObject:"
```

**Expected Output:** Should show the certificate properly formatted under `identityTrustAnchorsPEM`

---

## Step 4: Validate and Commit Changes

### 4.1 Check Git Status
```bash
git status
```

**Expected Output:**
```
modified:   applications/infrastructure/linkerd-control-plane.yaml
```

### 4.2 Review Changes
```bash
git diff applications/infrastructure/linkerd-control-plane.yaml
```

**Verify:**
- Certificate is properly indented
- No extra characters or line breaks
- File shows only additions (green +)

### 4.3 Stage Changes
```bash
git add applications/infrastructure/linkerd-control-plane.yaml
```

### 4.4 Commit Changes
```bash
git commit -m "fix: add trust anchor certificate to Linkerd control plane

- Add identityTrustAnchorsPEM to Helm values
- Fixes empty linkerd-identity-trust-roots ConfigMap
- Resolves CrashLoopBackOff on all Linkerd pods
- Fixes error: LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS must be set"
```

### 4.5 Push to Remote
```bash
git push origin master
```

**Expected Output:**
```
Enumerating objects: X, done.
To https://github.com/oNddleo/gitops.git
   753bc97..xxxxxxx  master -> master
```

---

## Step 5: Monitor ArgoCD Sync

### 5.1 Check ArgoCD Application Status
```bash
kubectl get application linkerd-control-plane -n argocd -w
```

**Watch for:**
```
NAME                     SYNC STATUS   HEALTH STATUS
linkerd-control-plane    Synced        Progressing
linkerd-control-plane    Synced        Healthy
```

Press `Ctrl+C` when status shows `Healthy`

### 5.2 Trigger Manual Sync (Optional)
If ArgoCD doesn't auto-sync immediately:
```bash
kubectl patch application linkerd-control-plane -n argocd \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'
```

### 5.3 Watch ArgoCD Sync Progress
```bash
kubectl describe application linkerd-control-plane -n argocd | tail -30
```

---

## Step 6: Verify the Fix

### 6.1 Check ConfigMap is Populated
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o yaml | grep -A 5 "ca-bundle.crt:"
```

**Expected Output:** ConfigMap now contains the certificate:
```yaml
ca-bundle.crt: |
  -----BEGIN CERTIFICATE-----
  MIIFKzCCAxOgAwIBAgIU...
```

### 6.2 Watch Pod Recovery
```bash
kubectl get pods -n linkerd -w
```

**Watch for pods transitioning:**
- `CrashLoopBackOff` → `Running` (old pods being terminated)
- New pods starting with `0/X` → `X/X Ready`

Press `Ctrl+C` once all pods are `Running`

### 6.3 Verify All Pods are Running
```bash
kubectl get pods -n linkerd
```

**Expected Output:** All pods should be `Running` with all containers ready:
```
NAME                                      READY   STATUS    RESTARTS   AGE
linkerd-destination-xxxxxxxxx-xxxxx       4/4     Running   0          2m
linkerd-identity-xxxxxxxxx-xxxxx          2/2     Running   0          2m
linkerd-proxy-injector-xxxxxxxxx-xxxxx    2/2     Running   0          2m
```

### 6.4 Check Pod Logs for Errors
```bash
kubectl logs -n linkerd -l linkerd.io/control-plane-component=destination --tail=20 | grep -i error
```

**Expected Output:** No error messages (empty output or only INFO logs)

### 6.5 Verify Environment Variable is Set
```bash
kubectl exec -n linkerd deployment/linkerd-destination -c linkerd-proxy -- \
  printenv LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS | head -5
```

**Expected Output:** Certificate content:
```
-----BEGIN CERTIFICATE-----
MIIFKzCCAxOgAwIBAgIU...
```

---

## Step 7: Verify Linkerd Functionality

### 7.1 Check Linkerd Control Plane Health
```bash
kubectl get deployment -n linkerd
```

**Expected Output:** All deployments should have READY matching AVAILABLE:
```
NAME                     READY   UP-TO-DATE   AVAILABLE
linkerd-destination      1/1     1            1
linkerd-identity         1/1     1            1
linkerd-proxy-injector   1/1     1            1
```

### 7.2 Test Proxy Injection (Optional)
Create a test pod to verify proxy injection works:
```bash
kubectl run test-pod --image=nginx --labels="linkerd.io/inject=enabled" -n default
```

Check if proxy sidecar is injected:
```bash
kubectl get pod test-pod -o jsonpath='{.spec.containers[*].name}'
```

**Expected Output:**
```
nginx linkerd-proxy
```

Cleanup:
```bash
kubectl delete pod test-pod
```

---

## Step 8: Document and Monitor

### 8.1 Update This Fix Document
Add completion timestamp:
```bash
echo "Fix completed at: $(date)" >> LINKERD_TRUST_ANCHOR_FIX.md
```

### 8.2 Monitor for 10 Minutes
```bash
watch -n 10 'kubectl get pods -n linkerd'
```

**Verify:** No pods restart or enter CrashLoopBackOff

Press `Ctrl+C` after monitoring period

### 8.3 Check ArgoCD Application is Healthy
```bash
kubectl get application -n argocd | grep linkerd
```

**Expected Output:** All Linkerd applications should show `Synced` and `Healthy`:
```
linkerd-control-plane    Synced    Healthy
linkerd-crds             Synced    Healthy
linkerd-viz              Synced    Healthy
```

---

## Troubleshooting

### If Pods Still Crash After Fix

**1. Check if ConfigMap updated:**
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o yaml
```
If still empty, force ArgoCD sync:
```bash
kubectl delete -n argocd application linkerd-control-plane
kubectl apply -f applications/infrastructure/linkerd-control-plane.yaml
```

**2. Check certificate format:**
```bash
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' | openssl x509 -noout -text
```
Should show valid certificate details without errors

**3. Manually populate ConfigMap (Emergency Fix):**
```bash
kubectl create configmap linkerd-identity-trust-roots \
  --from-literal=ca-bundle.crt="$(kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d)" \
  -n linkerd --dry-run=client -o yaml | kubectl apply -f -
```

**4. Check Helm values rendered correctly:**
```bash
kubectl get application linkerd-control-plane -n argocd -o yaml | grep -A 35 "valuesObject:"
```

### If ArgoCD Won't Sync

**Check ArgoCD Application Events:**
```bash
kubectl describe application linkerd-control-plane -n argocd
```

**Force Refresh:**
```bash
kubectl delete application linkerd-control-plane -n argocd
kubectl apply -f applications/infrastructure/linkerd-control-plane.yaml
```

---

## Verification Checklist

- [ ] Step 1: Verified problem exists (pods crashing)
- [ ] Step 2: Extracted trust anchor certificate from secret
- [ ] Step 3: Updated linkerd-control-plane.yaml with certificate
- [ ] Step 4: Committed and pushed changes to Git
- [ ] Step 5: ArgoCD synced successfully
- [ ] Step 6: ConfigMap populated with certificate
- [ ] Step 6: All Linkerd pods are Running
- [ ] Step 6: No error logs in proxy containers
- [ ] Step 7: Linkerd deployments are healthy
- [ ] Step 8: Monitored for stability (10+ minutes)

---

## Summary

**What We Fixed:**
- Added `identityTrustAnchorsPEM` to Linkerd Helm values
- This populates the `linkerd-identity-trust-roots` ConfigMap
- Proxy containers can now read trust anchors from the ConfigMap
- All Linkerd pods start successfully

**Key Files Modified:**
- `applications/infrastructure/linkerd-control-plane.yaml`

**How It Works:**
1. Helm chart reads `identityTrustAnchorsPEM` value
2. Creates/updates `linkerd-identity-trust-roots` ConfigMap with the certificate
3. Proxy containers read from ConfigMap via `LINKERD2_PROXY_IDENTITY_TRUST_ANCHORS` env var
4. Linkerd mTLS works correctly

---

## References

- [Linkerd Trust Anchors Documentation](https://linkerd.io/2/tasks/generate-certificates/)
- [Linkerd Helm Chart Values](https://github.com/linkerd/linkerd2/tree/main/charts/linkerd-control-plane)
- [Role of identityTrustAnchorsPEM Parameter](https://github.com/linkerd/linkerd2/discussions/6771)

---

**Fix Applied:** 2025-12-03
**Status:** ✓ Complete
