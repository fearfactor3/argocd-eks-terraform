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

variable "aws_lb_controller_chart_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart"
  type        = string
  default     = "1.13.2"
}

# Cross-stack inputs from the eks stack (injected by Spacelift as TF_VAR_*)
variable "eks_cluster_name" {
  description = "EKS cluster name from the eks stack"
  type        = string
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint from the eks stack"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate from the eks stack"
  type        = string
  sensitive   = true
}

variable "aws_lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller from the eks stack"
  type        = string
}
