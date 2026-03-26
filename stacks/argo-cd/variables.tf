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

variable "argocd_chart_version" {
  description = "Version of the Argo CD Helm chart"
  type        = string
  default     = "9.4.1"
}

variable "argocd_apps_chart_version" {
  description = "Version of the argocd-apps Helm chart (bootstraps AppProjects and Applications)"
  type        = string
  default     = "2.0.2"
}

variable "argocd_source_repo" {
  description = "Git repository URL ArgoCD is permitted to sync from. Set to the app manifests repo once ADR-006 is resolved. Defaults to '*' (any repo) until locked down."
  type        = string
  default     = "*"
}

variable "argocd_resource_profile" {
  description = "Resource requests/limits preset for ArgoCD pods. 'small' halves limits for dev t3.medium nodes; 'standard' applies production-grade sizing."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "standard"], var.argocd_resource_profile)
    error_message = "argocd_resource_profile must be \"small\" or \"standard\"."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN for ALB TLS termination. When set, the ALB uses HTTPS with SSL redirect. Leave empty (default) for HTTP-only — suitable for homelab until a domain is registered."
  type        = string
  default     = ""
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
