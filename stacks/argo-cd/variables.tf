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
  description = "Git repository URL ArgoCD is permitted to sync from. Set to your app manifests repo URL. Defaults to '*' (any repo) for initial bootstrap — lock this down before production. See docs/runbooks/connect-app-repo.md."
  type        = string
  default     = "*"

  # TODO(ADR-006): Re-enable this validation once the app manifests repo is
  # created and argocd_source_repo is set to its URL in stacks/spacelift/variables.tf
  # for the prod environment. Tracking: docs/decisions/006-argocd-app-repo.md
  #
  # validation {
  #   condition     = !(var.environment == "prod" && var.argocd_source_repo == "*")
  #   error_message = "argocd_source_repo must not be '*' in production — set it to your app repository URL before promoting to prod (see docs/runbooks/connect-app-repo.md)."
  # }
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
  description = "ACM certificate ARN for ALB TLS termination. When set, the ALB uses HTTPS with SSL redirect. Leave unset (default null) for HTTP-only — suitable for homelab until a domain is registered."
  type        = string
  default     = null
}

# Cross-stack inputs from the eks stack (injected by Spacelift as TF_VAR_*)
variable "eks_cluster_name" {
  description = "EKS cluster name from the eks stack"
  type        = string
  nullable    = false
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint from the eks stack"
  type        = string
  nullable    = false
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate from the eks stack"
  type        = string
  sensitive   = true
  nullable    = false
}
