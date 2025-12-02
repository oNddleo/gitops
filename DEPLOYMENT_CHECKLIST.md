# GitOps Platform Deployment Checklist

Use this checklist to ensure a successful deployment of the GitOps platform. For detailed instructions, refer to [README.md](./README.md#deployment-guide).

## Pre-Deployment

### AWS Resources

- [ ] EKS cluster created (v1.28+) with OIDC provider enabled
- [ ] ECR repository created for Docker images
- [ ] ECR repository created for Helm charts (OCI format)
- [ ] IAM role created for CSI Driver with IRSA
- [ ] VPC and subnets configured
- [ ] Security groups configured
- [ ] EKS node groups created

### Local Environment

- [ ] `kubectl` installed (v1.28+)
- [ ] `helm` installed (v3.14+)
- [ ] `aws-cli` installed and configured
- [ ] `argocd` CLI installed
- [ ] `step` CLI installed (for certificate generation)
- [ ] `terraform` installed

### Repository Configuration

- [ ] Repository cloned locally
- [ ] Repository URLs updated in all manifests
  - [ ] `bootstrap/root-app.yaml`
  - [ ] `applications/infrastructure-apps.yaml`
  - [ ] `applications/*/my-microservice.yaml`
- [ ] ECR registry URLs updated
- [ ] Domain names updated in ingress configurations
- [ ] IAM role ARNs updated in:
  - [ ] `infrastructure/secrets-store-csi/kustomization.yaml`
  - [ ] Helm chart `values.yaml` files for ServiceAccounts
- [ ] GitHub Actions secrets configured:
  - [ ] `AWS_ACCESS_KEY_ID`
  - [ ] `AWS_SECRET_ACCESS_KEY`
  - [ ] `ARGOCD_SERVER`
  - [ ] `ARGOCD_USERNAME`
  - [ ] `ARGOCD_PASSWORD`

## Phase 1: Deploy Terraform Infrastructure

- [ ] Terraform configuration reviewed and variables updated
- [ ] Connected to AWS: `aws configure`
- [ ] Executed: `terraform init`
- [ ] Executed: `terraform plan`
- [ ] Executed: `terraform apply`
- [ ] CSI Driver IAM role ARN captured
- [ ] IAM role verified: `aws iam get-role --role-name gitops-eks-cluster-secrets-csi-driver`
- [ ] IAM policy verified: `aws iam list-attached-role-policies --role-name gitops-eks-cluster-secrets-csi-driver`

## Phase 2: Bootstrap ArgoCD

- [ ] Connected to EKS cluster: `aws eks update-kubeconfig --name <cluster-name>`
- [ ] Verified cluster access: `kubectl cluster-info`
- [ ] Executed bootstrap script: `./bootstrap/install.sh`
- [ ] ArgoCD pods running: `kubectl get pods -n argocd`
- [ ] Retrieved ArgoCD admin password
- [ ] Accessed ArgoCD UI successfully
- [ ] Root App of Apps created: `kubectl get application infrastructure-apps -n argocd`

## Phase 3: Deploy Infrastructure Components

### Verify Infrastructure Apps Deployment

- [ ] CSI Driver deployed and healthy
  - [ ] Pods running: `kubectl get pods -n kube-system | grep csi`
  - [ ] DaemonSet ready: `kubectl get daemonset -n kube-system | grep secrets-store`
  - [ ] CSI Driver registered: `kubectl get csidriver secrets-store.csi.k8s.io`
- [ ] Traefik deployed and healthy
  - [ ] Pods running: `kubectl get pods -n traefik`
  - [ ] LoadBalancer created: `kubectl get svc -n traefik`
  - [ ] Dashboard accessible
- [ ] Linkerd deployed and healthy
  - [ ] Control plane running: `kubectl get pods -n linkerd`
  - [ ] Viz components running: `kubectl get pods -n linkerd-viz`
  - [ ] Linkerd check passed: `linkerd check`
- [ ] Reloader deployed: `kubectl get pods -n reloader`
- [ ] ArgoCD self-managed configuration applied

### Generate and Configure Linkerd Certificates

- [ ] Certificates generated: `cd infrastructure/linkerd && ./generate-certs.sh`
- [ ] Trust anchor secret created in Kubernetes
- [ ] Issuer certificate secret created in Kubernetes
- [ ] Certificates backed up securely
- [ ] Linkerd control plane restarted

## Phase 4: Create Secrets in AWS Secrets Manager

- [ ] Production secrets created:
  - [ ] `production/myapp/database`
  - [ ] `production/myapp/api-key`
- [ ] Staging secrets created:
  - [ ] `staging/myapp/database`
- [ ] Development secrets created:
  - [ ] `development/myapp/database`
- [ ] Secrets verified: `aws secretsmanager list-secrets --region us-east-1`
- [ ] Sample secret retrieved: `aws secretsmanager get-secret-value --secret-id production/myapp/database`

## Phase 5: Verify Infrastructure

- [ ] All ArgoCD infrastructure apps synced and healthy:
  ```bash
  kubectl get application -n argocd | grep infrastructure
  ```
- [ ] All infrastructure pods running
- [ ] Ingress LoadBalancer has external IP/hostname
- [ ] Dashboards accessible:
  - [ ] ArgoCD: `https://argocd.example.com`
  - [ ] Traefik: `https://traefik.example.com`
  - [ ] Linkerd: `https://linkerd.example.com`

## Phase 6: Deploy Applications

### Development Environment

- [ ] Development App of Apps deployed:
  ```bash
  kubectl apply -f applications/app-of-apps-dev.yaml
  ```
- [ ] Application synced: `argocd app sync my-microservice-dev`
- [ ] Pods running: `kubectl get pods -n development`
- [ ] SecretProviderClass created: `kubectl get secretproviderclass -n development`
- [ ] Secrets mounted in pod: `kubectl exec -n development <pod> -- ls -la /mnt/secrets`
- [ ] Kubernetes Secret synced: `kubectl get secret my-microservice-secrets -n development`
- [ ] Application health check passing
- [ ] Application logs healthy

### Staging Environment

- [ ] Staging App of Apps deployed:
  ```bash
  kubectl apply -f applications/app-of-apps-staging.yaml
  ```
- [ ] Application synced: `argocd app sync my-microservice-staging`
- [ ] Pods running: `kubectl get pods -n staging`
- [ ] SecretProviderClass created: `kubectl get secretproviderclass -n staging`
- [ ] Secrets mounted in pod: `kubectl exec -n staging <pod> -- ls -la /mnt/secrets`
- [ ] Kubernetes Secret synced: `kubectl get secret my-microservice-secrets -n staging`
- [ ] Application health check passing

### Production Environment

**Pre-deployment validation:**
- [ ] Dev and Staging deployments successful
- [ ] All tests passing
- [ ] Monitoring and alerting configured
- [ ] Rollback plan documented
- [ ] Team notified of deployment
- [ ] Maintenance window scheduled (if needed)

**Deployment:**
- [ ] Production App of Apps deployed:
  ```bash
  kubectl apply -f applications/app-of-apps-production.yaml
  ```
- [ ] Application synced: `argocd app sync my-microservice-production`
- [ ] Pods running: `kubectl get pods -n production`
- [ ] SecretProviderClass created: `kubectl get secretproviderclass -n production`
- [ ] Secrets mounted in all pods: verified via `kubectl exec`
- [ ] Kubernetes Secret synced: `kubectl get secret my-microservice-secrets -n production`
- [ ] Service health checks passing
- [ ] External endpoint accessible: `curl https://myapp.example.com/health`
- [ ] Metrics/monitoring functional

## Phase 7: Verify Service Mesh

- [ ] Namespaces have Linkerd injection enabled:
  ```bash
  kubectl get namespace production -o yaml | grep linkerd.io/inject
  ```
- [ ] Pods have Linkerd proxy injected:
  ```bash
  kubectl get pods -n production -o yaml | grep linkerd-proxy
  ```
- [ ] mTLS working: `linkerd viz stat deployment -n production`
- [ ] Traffic visualization available: `linkerd viz dashboard`

## CI/CD Pipeline

### GitHub Actions Configuration

- [ ] Workflows exist in `.github/workflows/`
- [ ] Secrets configured in GitHub repository settings
- [ ] ECR login working in CI
- [ ] Helm lint workflow passing
- [ ] Docker build workflow passing

### Test CI/CD Flow

- [ ] Make a test commit to develop branch
- [ ] CI pipeline triggered
- [ ] Docker image built and pushed to ECR
- [ ] Helm chart packaged and pushed to ECR
- [ ] Git repository updated with new image tag
- [ ] ArgoCD detected change and synced
- [ ] Application deployed successfully
- [ ] Total time < 5 minutes ✅

## Validation & Testing

### End-to-End Tests

- [ ] Application accessible via ingress URL
- [ ] HTTPS working with valid certificate
- [ ] Application returns expected response
- [ ] Database connection working (if applicable)
- [ ] Secrets loaded correctly from AWS Secrets Manager

### GitOps Flow

- [ ] Manual `kubectl` changes reverted by ArgoCD (self-heal)
- [ ] Git commit triggers deployment
- [ ] AWS Secrets Manager secret change triggers pod reload
- [ ] ConfigMap change triggers pod reload

### Secret Rotation Testing

- [ ] Updated secret in AWS Secrets Manager:
  ```bash
  aws secretsmanager update-secret \
    --secret-id production/myapp/database \
    --secret-string '{"password":"NEW_PASSWORD"}' \
    --region us-east-1
  ```
- [ ] Waited for CSI Driver sync (2 minutes)
- [ ] Secret file updated in pod: `kubectl exec -n production <pod> -- cat /mnt/secrets/database-password`
- [ ] Kubernetes Secret updated: `kubectl get secret my-microservice-secrets -n production`
- [ ] Reloader triggered rolling update: `kubectl get events -n production | grep Reloader`
- [ ] Pods restarted with new secret

### High Availability

- [ ] Multiple replicas running
- [ ] HPA scaling works
- [ ] Pod disruption budget set
- [ ] Node failure doesn't cause downtime (optional)

### Security

- [ ] mTLS enabled between services
- [ ] Secrets not stored in Git
- [ ] RBAC configured
- [ ] Network policies applied (optional)
- [ ] Pod security standards enforced

## Post-Deployment

### Documentation

- [ ] README.md updated with cluster-specific information
- [ ] Custom configurations documented
- [ ] Runbooks created for common operations
- [ ] Backup/restore procedures documented

### Monitoring Setup

- [ ] Prometheus collecting metrics (optional, future enhancement)
- [ ] Grafana dashboards created (optional)
- [ ] Alerts configured (optional)
- [ ] Log aggregation setup (optional)

### Backups

- [ ] Linkerd certificates backed up securely
- [ ] ArgoCD applications exported: `kubectl get application -n argocd -o yaml > argocd-backup.yaml`
- [ ] AWS Secrets Manager secrets inventory: `aws secretsmanager list-secrets > secrets-inventory.json`
- [ ] Helm charts backed up in ECR

### Team Training

- [ ] Team trained on GitOps workflow
- [ ] Team has access to ArgoCD UI
- [ ] Team knows how to deploy applications
- [ ] Team knows how to troubleshoot issues
- [ ] Team understands secret management with AWS Secrets Manager + CSI Driver

### Operational Readiness

- [ ] On-call rotation established
- [ ] Incident response procedures documented
- [ ] Disaster recovery plan created
- [ ] Maintenance windows scheduled

## Success Criteria

Verify all success criteria are met:

- [ ] ✅ Commit to code triggers automatic deployment in < 5 minutes
- [ ] ✅ AWS Secrets Manager secret changes automatically rollout pods
- [ ] ✅ Traefik dashboard accessible and shows IngressRoutes
- [ ] ✅ ArgoCD UI shows all apps as "Healthy" and "Synced"
- [ ] ✅ `kubectl get application -n argocd` shows all apps
- [ ] ✅ Service mesh mTLS enabled by default
- [ ] ✅ No manual `kubectl` commands needed for deployments
- [ ] ✅ All secrets managed by AWS Secrets Manager, none in Git
- [ ] ✅ CSI Driver mounting secrets as volumes in pods
- [ ] ✅ Reloader triggering rolling updates on secret changes

## Rollback Plan

In case of issues:

**Infrastructure Issues:**
```bash
# Disable auto-sync
argocd app set <app-name> --sync-policy none

# Revert to previous Git commit
git revert <commit-hash>
git push

# Sync ArgoCD
argocd app sync <app-name>
```

**Application Issues:**
```bash
# Roll back to previous image
cd charts/my-microservice/ci
# Update image tag to previous version
git commit -m "rollback: revert to v1.0.0"
git push
```

**Secret Issues:**
```bash
# Revert secret in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id production/myapp/database \
  --secret-string '<previous-value>' \
  --region us-east-1
```

---

## Notes

- Keep this checklist updated as the platform evolves
- Document any deviations from the standard deployment
- Share lessons learned with the team
- For detailed deployment instructions, refer to [README.md](./README.md#deployment-guide)

---

**Last Updated:** 2025-12-02
**Platform Version:** 2.0.0 (AWS Secrets Manager)
