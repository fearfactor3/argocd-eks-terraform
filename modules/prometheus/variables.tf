variable "release_name" {
  description = "Name of the Helm release for Argo CD"
  type        = string
  default     = "prometheus"
}

variable "namespace" {
  description = "Namespace to install Argo CD into"
  type        = string
  default     = "prometheus"
}

variable "create_namespace" {
  description = "Whether to create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Timeout in seconds to wait for any individual Kubernetes operation (like Jobs for hooks, etc.)"
  type        = number
  default     = 2000
}

variable "helm_repo_url" {
  description = "Helm repository URL for Argo CD"
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "chart_name" {
  description = "Name of the Helm chart to install"
  type        = string
  default     = "kube-prometheus-stack"
}

variable "chart_version" {
  description = "Version of the Helm chart"
  type        = string
  default     = "62.3.1"
}

variable "values" {
  description = "Custom values to override Helm chart defaults"
  type        = map(string)
  default = {
    "podSecurityPolicy.enabled"       = true
    "server.persistentVolume.enabled" = true
    "grafana.service.type"            = "LoadBalancer"
    "prometheus.service.type"         = "LoadBalancer"
  }
}
