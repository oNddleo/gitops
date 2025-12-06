# Destroy Scripts Documentation

This directory contains several scripts for destroying ArgoCD applications and cleaning up resources.

## Available Scripts

### 1. `destroy.sh` - Complete Destruction

**Purpose**: Destroys all applications, infrastructure, and optionally ArgoCD itself.

**What it does**:
- Deletes all VSF-Miniapp services (service-a, service-b) across all environments (dev, staging, production)
- Deletes ApplicationSets
- Deletes infrastructure applications (Linkerd, Traefik, Secrets Store CSI, Reloader, etc.)
- Cleans up all namespaces
- Optionally destroys ArgoCD itself

**What it preserves**:
- EKS cluster and nodes
- AWS Secrets Manager secrets
- AWS IAM roles and policies
- ECR repositories and images
- Git repository contents

**Usage**:
```bash
./destroy.sh
```

**When to use**: When you want to completely tear down the platform but keep the EKS cluster.

---

### 2. `destroy-services-only.sh` - Services Only

**Purpose**: Destroys only the VSF-Miniapp services, preserving all infrastructure.

**What it does**:
- Deletes service-a and service-b from all environments
- Deletes the services ApplicationSet
- Cleans up service namespaces (dev, staging, production)

**What it preserves**:
- All infrastructure (ArgoCD, Linkerd, Traefik, etc.)
- Infrastructure namespaces
- Cluster configuration

**Usage**:
```bash
./destroy-services-only.sh
```

**When to use**: When you want to remove applications but keep infrastructure for redeployment.

---

### 3. `destroy-environment.sh` - Specific Environment

**Purpose**: Destroys services from a single environment only.

**What it does**:
- Prompts you to choose an environment (dev, staging, or production)
- Deletes all services from that environment only
- Cleans up the environment namespace

**What it preserves**:
- Services in other environments
- All infrastructure
- Other environment namespaces

**Usage**:
```bash
./destroy-environment.sh
```

**Interactive prompts**:
1. Choose environment (1=dev, 2=staging, 3=production)
2. Confirm destruction

**When to use**: When you want to tear down just one environment (e.g., removing dev after testing).

---

### 4. `force-cleanup.sh` - Emergency Cleanup

**Purpose**: Forcefully removes stuck resources and finalizers.

**What it does**:
- Removes finalizers from stuck namespaces
- Force deletes stuck ArgoCD applications
- Removes stuck pods, PVCs, and deployments
- Cleans up webhook configurations
- Removes orphaned resources

**Requires**: `jq` command-line tool must be installed

**Usage**:
```bash
./force-cleanup.sh
```

**Confirmation**: Requires typing "FORCE" to confirm (more dangerous operation)

**When to use**: Only when normal destroy scripts fail and resources are stuck in "Terminating" state.

---

## Recommended Workflow

### Standard Teardown Process

1. **Destroy services first** (optional, if you want to keep infrastructure):
   ```bash
   ./destroy-services-only.sh
   ```

2. **Or destroy everything**:
   ```bash
   ./destroy.sh
   ```

3. **If resources get stuck**, use force cleanup:
   ```bash
   ./force-cleanup.sh
   ```

### Environment-Specific Teardown

1. **Remove a specific environment**:
   ```bash
   ./destroy-environment.sh
   # Choose environment when prompted
   ```

2. **Verify deletion**:
   ```bash
   kubectl get applications -n argocd
   kubectl get namespaces
   ```

---

## Safety Features

All scripts include:
- ✅ Cluster connectivity checks
- ✅ Confirmation prompts before destructive operations
- ✅ Color-coded output (warnings in yellow, errors in red, success in green)
- ✅ Graceful degradation (continues even if some resources don't exist)
- ✅ ArgoCD CLI detection (uses `argocd` command if available, falls back to `kubectl`)

---

## Common Issues and Solutions

### Issue: Namespace Stuck in "Terminating"

**Symptom**: Namespace shows as "Terminating" for a long time.

**Solution**:
```bash
# Run force cleanup
./force-cleanup.sh

# Or manually remove finalizers
kubectl get namespace <namespace> -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw /api/v1/namespaces/<namespace>/finalize -f -
```

### Issue: ArgoCD Application Won't Delete

**Symptom**: Application stuck in deletion with finalizers.

**Solution**:
```bash
# Use force cleanup script
./force-cleanup.sh

# Or manually patch
kubectl patch application <app-name> -n argocd \
  --type json \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

### Issue: PVC Stuck in Terminating

**Symptom**: PersistentVolumeClaim won't delete.

**Solution**:
```bash
# Force cleanup handles this
./force-cleanup.sh

# Or manually
kubectl patch pvc <pvc-name> -n <namespace> \
  --type json \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

### Issue: Webhook Preventing Deletion

**Symptom**: Resources fail to delete with webhook errors.

**Solution**:
```bash
# Remove validating webhooks
kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/name=linkerd

# Remove mutating webhooks
kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/name=linkerd
```

---

## What Gets Deleted

### Kubernetes Resources

| Resource Type | destroy.sh | destroy-services-only.sh | destroy-environment.sh |
|---------------|-----------|--------------------------|------------------------|
| Service Applications | ✅ | ✅ | ✅ (selected env only) |
| Infrastructure Apps | ✅ | ❌ | ❌ |
| ApplicationSets | ✅ | ✅ (services only) | ❌ |
| Service Namespaces | ✅ | ✅ | ✅ (selected env only) |
| Infrastructure Namespaces | ✅ | ❌ | ❌ |
| ArgoCD | ⚠️ (optional) | ❌ | ❌ |

### What is NEVER Deleted

These scripts **DO NOT** delete:
- ❌ EKS cluster
- ❌ AWS Secrets Manager secrets
- ❌ IAM roles and policies
- ❌ ECR repositories
- ❌ Docker images
- ❌ Git repository
- ❌ Terraform state
- ❌ AWS infrastructure

---

## AWS Resources Cleanup

After running destroy scripts, you may want to clean up AWS resources:

### Delete Secrets

```bash
# List all secrets
aws secretsmanager list-secrets --region us-east-1

# Delete specific secrets
aws secretsmanager delete-secret \
  --secret-id dev/vsf-miniapp/service-a/database \
  --region us-east-1 \
  --force-delete-without-recovery

aws secretsmanager delete-secret \
  --secret-id dev/vsf-miniapp/service-b/mongodb \
  --region us-east-1 \
  --force-delete-without-recovery
```

### Delete ECR Repositories

```bash
# List repositories
aws ecr describe-repositories --region us-east-1

# Delete repository
aws ecr delete-repository \
  --repository-name vsf-miniapp/service-a \
  --region us-east-1 \
  --force
```

### Destroy Terraform Infrastructure

```bash
# From the terraform directory
cd terraform
terraform destroy
```

---

## Verification Commands

After running destroy scripts, verify cleanup:

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check ApplicationSets
kubectl get applicationsets -n argocd

# Check namespaces
kubectl get namespaces

# Check for stuck resources
kubectl get namespaces --field-selector status.phase=Terminating

# Check pods in all namespaces
kubectl get pods --all-namespaces

# Check PVCs
kubectl get pvc --all-namespaces
```

---

## Prerequisites

All scripts require:
- `kubectl` - Kubernetes CLI
- Valid kubeconfig with cluster access
- Appropriate RBAC permissions

`force-cleanup.sh` additionally requires:
- `jq` - JSON processor

Install jq:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# RHEL/CentOS
sudo yum install jq
```

---

## Script Execution Permissions

Make scripts executable:
```bash
chmod +x destroy.sh
chmod +x destroy-services-only.sh
chmod +x destroy-environment.sh
chmod +x force-cleanup.sh
```

---

## Safety Tips

1. **Always backup first**: Ensure you have backups of important data
2. **Test in dev first**: Try destroy scripts in dev environment before production
3. **Check twice, delete once**: Verify what will be deleted before confirming
4. **Use specific scripts**: Prefer `destroy-environment.sh` or `destroy-services-only.sh` over full `destroy.sh`
5. **Monitor deletion**: Watch the output for errors or stuck resources
6. **Keep infrastructure**: Usually safer to keep infrastructure and just destroy services

---

## Emergency Contacts

If you encounter issues:

1. **Check documentation**: Review the main README.md and troubleshooting guides
2. **Review logs**: Check ArgoCD and application logs
3. **Community support**: Reach out to the ArgoCD community
4. **Kubernetes events**: Check for relevant events with `kubectl get events --all-namespaces`

---

## Related Documentation

- [Main README](../README.md) - Platform overview
- [GETTING_STARTED.md](docs/GETTING_STARTED.md) - Deployment guide
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues
- [CLAUDE.md](../CLAUDE.md) - Development guidelines

---

**Last Updated**: 2025-12-06
**Version**: 1.0.0
