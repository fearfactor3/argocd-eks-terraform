variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "kyverno_chart_version" {
  description = "Version of the Kyverno Helm chart"
  type        = string
  default     = "3.5.3" # 3.3.x used bitnami/kubectl:1.30.2 which does not exist on Docker Hub
}

variable "kyverno_policies_chart_version" {
  description = "Version of the kyverno-policies Helm chart"
  type        = string
  default     = "3.5.3"
}

# Cross-stack inputs from the eks-addons stack (injected by Spacelift as TF_VAR_*)
variable "eks_cluster_name" {
  description = "EKS cluster name from the eks-addons stack"
  type        = string
  nullable    = false
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint from the eks-addons stack"
  type        = string
  nullable    = false
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate from the eks-addons stack"
  type        = string
  sensitive   = true
  nullable    = false
}
