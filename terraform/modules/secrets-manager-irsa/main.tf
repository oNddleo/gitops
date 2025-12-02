data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM Policy for Secrets Manager read access
resource "aws_iam_policy" "secrets_manager_read" {
  name        = "${var.cluster_name}-secrets-manager-read"
  description = "Allow EKS pods to read secrets from AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_prefix}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-secrets-manager-read"
    }
  )
}

# OIDC Provider data source (created by EKS module)
data "aws_iam_openid_connect_provider" "eks" {
  url = var.oidc_provider_url
}

# IAM Role for Service Account (IRSA)
resource "aws_iam_role" "secrets_csi_driver" {
  name               = "${var.cluster_name}-secrets-csi-driver"
  description        = "IAM role for Secrets Store CSI Driver to access AWS Secrets Manager"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}",
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-secrets-csi-driver"
    }
  )
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "secrets_manager_read" {
  role       = aws_iam_role.secrets_csi_driver.name
  policy_arn = aws_iam_policy.secrets_manager_read.arn
}
