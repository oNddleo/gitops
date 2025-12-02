# GitOps Platform Deployment Checklist

Use this checklist to ensure a successful deployment of the GitOps platform.

## Pre-Deployment

### AWS Resources

- [ ] EKS cluster created (v1.28+)
- [ ] ECR repository created for Docker images
- [ ] ECR repository created for Helm charts
- [ ] DynamoDB table created for Vault (`vault-data`)
- [ ] S3 bucket created for Vault snapshots
- [ ] KMS key created for Vault auto-unseal
- [ ] IAM role created for Vault with IRSA
- [ ] VPC and subnets configured
- [ ] Security groups configured
- [ ] EKS node groups created

### Local Environment

- [ ] `kubectl` installed (v1.28+)
- [ ] `helm` installed (v3.14+)
- [ ] `aws-cli` installed and configured
- [ ] `argocd` CLI installed
- [ ] `step` CLI installed (for certificate generation)
- [ ] `terraform` installed (optional)

### Repository Configuration

- [ ] Repository cloned locally
- [ ] Repository URLs updated in all manifests
  - [ ] `bootstrap/root-app.yaml`
  - [ ] `applications/infrastructure-apps.yaml`
  - [ ] `applications/*/my-microservice.yaml`
- [ ] ECR registry URLs updated
- [ ] Domain names updated in ingress configurations
- [ ] GitHub Actions secrets configured:
  - [ ] `AWS_ACCESS_KEY_ID`
  - [ ] `AWS_SECRET_ACCESS_KEY`
  - [ ] `ARGOCD_SERVER`
  - [ ] `ARGOCD_USERNAME`
  - [ ] `ARGOCD_PASSWORD`

## Infrastructure Deployment

### 1. Bootstrap ArgoCD

- [ ] Connected to EKS cluster: `aws eks update-kubeconfig --name <cluster-name>`
- [ ] Verified cluster access: `kubectl cluster-info`
- [ ] Executed bootstrap script: `./bootstrap/install.sh`
- [ ] ArgoCD pods running: `kubectl get pods -n argocd`
- [ ] Retrieved ArgoCD admin password
- [ ] Accessed ArgoCD UI successfully
- [ ] Root App of Apps created: `kubectl get application infrastructure-apps -n argocd`

### 2. Generate Certificates

- [ ] Linkerd certificates generated: `cd infrastructure/linkerd && ./generate-certs.sh`
- [ ] Trust anchor secret created in Kubernetes
- [ ] Issuer certificate secret created in Kubernetes
- [ ] Certificates backed up securely

### 3. Deploy Infrastructure Components

- [ ] Vault deployed and healthy
  - [ ] Pods running: `kubectl get pods -n vault`
  - [ ] Service accessible: `kubectl get svc -n vault`
  - [ ] Vault initialized
  - [ ] Vault unsealed
  - [ ] Kubernetes auth enabled
  - [ ] Policies created
- [ ] Traefik deployed and healthy
  - [ ] Pods running: `kubectl get pods -n traefik`
  - [ ] LoadBalancer created: `kubectl get svc -n traefik`
  - [ ] Dashboard accessible
- [ ] Linkerd deployed and healthy
  - [ ] Control plane running: `kubectl get pods -n linkerd`
  - [ ] Viz components running: `kubectl get pods -n linkerd-viz`
  - [ ] Linkerd check passed: `linkerd check`
- [ ] Reloader deployed: `kubectl get pods -n reloader`
- [ ] External Secrets Operator deployed: `kubectl get pods -n external-secrets-system`
- [ ] ArgoCD self-managed configuration applied

### 4. Configure Vault

- [ ] Port-forward to Vault: `kubectl port-forward -n vault svc/vault 8200:8200`
- [ ] Logged in to Vault: `vault login <token>`
- [ ] Kubernetes auth configured
- [ ] ArgoCD policy created
- [ ] External Secrets policy created
- [ ] Application policies created (dev, staging, production)
- [ ] Kubernetes roles created
- [ ] Example secrets created:
  - [ ] `secret/production/myapp/database`
  - [ ] `secret/staging/myapp/database`
  - [ ] `secret/development/myapp/database`
  - [ ] `secret/shared/config`

### 5. Verify Infrastructure

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
  - [ ] Vault: `https://vault.example.com`

## Application Deployment

### 1. Deploy Environment App of Apps

- [ ] Production App of Apps deployed:

  ```bash
  kubectl apply -f applications/app-of-apps-production.yaml
  ```

- [ ] Staging App of Apps deployed:

  ```bash
  kubectl apply -f applications/app-of-apps-staging.yaml
  ```

- [ ] Development App of Apps deployed:

  ```bash
  kubectl apply -f applications/app-of-apps-dev.yaml
  ```

### 2. Verify Application Deployments

- [ ] All application ArgoCD apps created: `kubectl get application -n argocd`
- [ ] All apps synced and healthy: `argocd app list`
- [ ] Application namespaces created:
  - [ ] `production`
  - [ ] `staging`
  - [ ] `development`
- [ ] Application pods running in each namespace
- [ ] ExternalSecrets synced: `kubectl get externalsecret -A`
- [ ] Secrets created from Vault: `kubectl get secret -n production`

### 3. Verify Service Mesh

- [ ] Namespaces have Linkerd injection enabled:

  ```bash
  kubectl get namespace production -o yaml | grep linkerd.io/inject
  ```

- [ ] Pods have Linkerd proxy injected:

  ```bash
  kubectl get pods -n production -o yaml | grep linkerd-proxy
  ```

- [ ] mTLS working: `linkerd viz stat deployment -n production`

## CI/CD Pipeline

### 1. GitHub Actions Configuration

- [ ] Workflows exist in `.github/workflows/`
- [ ] Secrets configured in GitHub repository settings
- [ ] ECR login working in CI
- [ ] Helm lint workflow passing
- [ ] Docker build workflow passing

### 2. Test CI/CD Flow

- [ ] Make a test commit to develop branch
- [ ] CI pipeline triggered
- [ ] Docker image built and pushed to ECR
- [ ] Helm chart packaged and pushed to ECR
- [ ] Git repository updated with new image tag
- [ ] ArgoCD detected change and synced
- [ ] Application deployed successfully
- [ ] Total time < 5 minutes ✅

## Validation & Testing

### 1. End-to-End Tests

- [ ] Application accessible via ingress URL
- [ ] HTTPS working with valid certificate
- [ ] Application returns expected response
- [ ] Database connection working (if applicable)
- [ ] Secrets loaded correctly from Vault

### 2. GitOps Flow

- [ ] Manual `kubectl` changes reverted by ArgoCD (self-heal)
- [ ] Git commit triggers deployment
- [ ] Vault secret change triggers pod reload
- [ ] ConfigMap change triggers pod reload

### 3. High Availability

- [ ] Multiple replicas running
- [ ] HPA scaling works
- [ ] Pod disruption budget set
- [ ] Node failure doesn't cause downtime

### 4. Security

- [ ] mTLS enabled between services
- [ ] Secrets not stored in Git
- [ ] RBAC configured
- [ ] Network policies applied (optional)
- [ ] Pod security standards enforced

## Post-Deployment

### 1. Documentation

- [ ] Update README with cluster-specific information
- [ ] Document custom configurations
- [ ] Create runbooks for common operations
- [ ] Document backup/restore procedures

### 2. Monitoring Setup

- [ ] Prometheus collecting metrics
- [ ] Grafana dashboards created
- [ ] Alerts configured
- [ ] Log aggregation setup

### 3. Backups

- [ ] Vault snapshot taken and stored securely
- [ ] ArgoCD applications exported
- [ ] Helm charts backed up
- [ ] Linkerd certificates backed up

### 4. Team Training

- [ ] Team trained on GitOps workflow
- [ ] Team has access to ArgoCD UI
- [ ] Team knows how to deploy applications
- [ ] Team knows how to troubleshoot issues

### 5. Operational Readiness

- [ ] On-call rotation established
- [ ] Incident response procedures documented
- [ ] Disaster recovery plan created
- [ ] Maintenance windows scheduled

## Success Criteria

Verify all success criteria are met:

- [ ] ✅ Commit to code triggers automatic deployment in < 5 minutes
- [ ] ✅ Vault secret changes automatically rollout pods
- [ ] ✅ Traefik dashboard accessible and shows IngressRoutes
- [ ] ✅ ArgoCD UI shows all apps as "Healthy" and "Synced"
- [ ] ✅ `kubectl get application -n argocd` shows all apps
- [ ] ✅ Service mesh mTLS enabled by default
- [ ] ✅ No manual `kubectl` commands needed for deployments
- [ ] ✅ All secrets managed by Vault, none in Git

## Rollback Plan

In case of issues:

1. **Infrastructure Issues:**

   ```bash
   # Disable auto-sync
   argocd app set <app-name> --sync-policy none

   # Revert to previous Git commit
   git revert <commit-hash>
   git push

   # Sync ArgoCD
   argocd app sync <app-name>
   ```

2. **Application Issues:**

   ```bash
   # Roll back to previous image
   cd charts/my-microservice/ci
   # Update image tag to previous version
   git commit -m "rollback: revert to v1.0.0"
   git push
   ```

3. **Vault Issues:**

   ```bash
   # Restore from snapshot
   vault operator raft snapshot restore backup.snap
   ```

---

## Notes

- Keep this checklist updated as the platform evolves
- Document any deviations from the standard deployment
- Share lessons learned with the team

---

**Last Updated:** 2025-01-25
