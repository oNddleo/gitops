# Operations & Maintenance Guide

## 🛠 Daily Operations

### Status Checks
```bash
# App Status
argocd app list

# Infrastructure Health
kubectl get pods -n linkerd
kubectl get pods -n traefik
kubectl get pods -n kube-system | grep csi
```

### Manage Secrets
**Create/Update Secret:**
```bash
aws secretsmanager create-secret --name production/myapp/db \
  --secret-string '{"password":"new"}' --region us-east-1
```
*Note: CSI driver polls every 2 mins. Reloader auto-restarts pods.*

### Scaling
```bash
# Via Git (Recommended)
vim charts/vsf-miniapp/ci/service-a-production.yaml
# Update replicaCount: 5
git commit -m "scale up" && git push
```

---

## 📊 Monitoring & Observability

### Key Metrics Endpoints
The platform exposes Prometheus metrics at standard endpoints:

*   **Traefik:** `:9100/metrics`
*   **ArgoCD:** `:8082/metrics`
*   **Linkerd:** `:4191/metrics`
*   **Applications:** `:8080/metrics` (or configured port)

### Success Criteria Validation
Use these checks to verify platform health:

1.  **Automated Deployment:** Commit to main -> Production update < 5 mins.
2.  **Secret Rotation:** Update AWS Secret -> Pods restart automatically (2-5 mins).
3.  **Dashboard Access:** Traefik, ArgoCD, and Linkerd dashboards are accessible.
4.  **Service Mesh:** `linkerd viz stat` shows 100% mTLS success rate.

---

## 🔄 Maintenance

### Certificate Rotation (Linkerd)
Linkerd certificates expire every year. To rotate:
1. Run `infrastructure/linkerd/generate-certs.sh`
2. Update `linkerd-identity-issuer` secret.
3. Restart Linkerd control plane: `kubectl rollout restart deploy -n linkerd`.

### Backup
- **ArgoCD:** `kubectl get app -A -o yaml > apps-backup.yaml`
- **Secrets:** AWS Secrets Manager handles backups/recovery (30 days).

---

## 🆘 Troubleshooting Cheat Sheet

### Pods Stuck in `Init:0/1`
**Cause:** Secret mount failure.
**Fix:** Check `kubectl describe pod`. Verify IAM Role (IRSA) and Secret name in AWS.

### 502 Bad Gateway
**Cause:** Application down or not ready.
**Fix:** Check `kubectl logs`. Verify Readiness Probe paths in `values.yaml`.

### App Not Syncing
**Cause:** Git/Helm error.
**Fix:** `argocd app get <name>` to see error. `argocd app sync <name> --prune` to force.

### Linkerd Issues
**Check:** `linkerd check`
**Fix:** Check Trust Anchors (see `TROUBLESHOOTING.md`).