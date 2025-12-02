variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "secrets-store-csi-driver"
}

variable "secret_prefix" {
  description = "Prefix for secrets in AWS Secrets Manager (e.g., 'production', 'staging', or '*' for all)"
  type        = string
  default     = "*"
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
