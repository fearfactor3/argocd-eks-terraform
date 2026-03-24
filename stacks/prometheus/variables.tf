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

variable "prometheus_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "81.5.0"
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

variable "prometheus_storage_size" {
  description = "EBS volume size for Prometheus metrics storage. 10Gi suits dev (short retention); increase for prod based on scrape interval and cardinality."
  type        = string
  default     = "50Gi"
}

variable "loki_storage_size" {
  description = "EBS volume size for Loki log storage. 5Gi suits dev; increase for prod based on log volume and retention period."
  type        = string
  default     = "10Gi"
}

variable "pss_restricted_warn" {
  description = "When true, adds warn/audit=restricted Pod Security Standard labels to the prometheus namespace. Surfaces hardening gaps without blocking pods. Disable in dev to reduce noise."
  type        = bool
  default     = false
}

variable "loki_chart_version" {
  description = "Version of the Loki Helm chart"
  type        = string
  default     = "6.55.0"
}

variable "alloy_chart_version" {
  description = "Version of the Grafana Alloy Helm chart"
  type        = string
  default     = "1.6.2"
}
