# AWS Secrets Manager IRSA Module

This Terraform module creates IAM roles and policies for the Kubernetes Secrets Store CSI Driver to access AWS Secrets Manager using IRSA (IAM Roles for Service Accounts).

## Features

- Creates IAM policy with least-privilege access to AWS Secrets Manager
- Creates IAM role with OIDC trust relationship for EKS service accounts
- Supports secret prefix filtering for environment isolation
- Fully compatible with the Secrets Store CSI Driver

## Usage

```hcl
module "secrets_manager_irsa" {
  source = "./modules/secrets-manager-irsa"

  cluster_name       = "gitops-eks-cluster"
  oidc_provider_url  = module.eks.cluster_oidc_issuer_url
  namespace          = "kube-system"
  service_account_name = "secrets-store-csi-driver"
  secret_prefix      = "*"  # Allow access to all secrets

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | EKS cluster name | `string` | n/a | yes |
| oidc_provider_url | EKS OIDC provider URL | `string` | n/a | yes |
| namespace | Kubernetes namespace for the service account | `string` | `"kube-system"` | no |
| service_account_name | Kubernetes service account name | `string` | `"secrets-store-csi-driver"` | no |
| secret_prefix | Prefix for secrets in AWS Secrets Manager | `string` | `"*"` | no |
| tags | Additional tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| role_arn | IAM role ARN for the CSI driver service account |
| role_name | IAM role name for the CSI driver service account |
| policy_arn | IAM policy ARN for Secrets Manager access |
| policy_name | IAM policy name for Secrets Manager access |

## Secret Prefix Examples

- `*` - Allow access to all secrets (not recommended for production)
- `production/*` - Allow access only to secrets starting with `production/`
- `{production,staging}/*` - Allow access to production and staging secrets

## IAM Policy

The module creates a policy that allows:
- `secretsmanager:GetSecretValue` - Retrieve secret values
- `secretsmanager:DescribeSecret` - Get secret metadata
- `secretsmanager:ListSecrets` - List available secrets

## Notes

- The OIDC provider must be created before using this module (typically done by EKS module)
- The service account must be annotated with `eks.amazonaws.com/role-arn` in Kubernetes
- Secrets must be created in AWS Secrets Manager before pods can access them
