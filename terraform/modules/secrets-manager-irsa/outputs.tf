output "role_arn" {
  description = "IAM role ARN for the CSI driver service account"
  value       = aws_iam_role.secrets_csi_driver.arn
}

output "role_name" {
  description = "IAM role name for the CSI driver service account"
  value       = aws_iam_role.secrets_csi_driver.name
}

output "policy_arn" {
  description = "IAM policy ARN for Secrets Manager access"
  value       = aws_iam_policy.secrets_manager_read.arn
}

output "policy_name" {
  description = "IAM policy name for Secrets Manager access"
  value       = aws_iam_policy.secrets_manager_read.name
}
