variable "release_name" {
  description = "Name of the Helm release for Argo CD"
  type        = string
  default     = "argo-cd"
}

variable "namespace" {
  description = "Namespace to install Argo CD into"
  type        = string
  default     = "argo-cd"
}

variable "create_namespace" {
  description = "Whether to create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "helm_repo_url" {
  description = "Helm repository URL for Argo CD"
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "chart_name" {
  description = "Name of the Helm chart to install"
  type        = string
  default     = "argo-cd"
}

variable "chart_version" {
  description = "Version of the Helm chart"
  type        = string
  default     = "7.7.1"
}

variable "values" {
  description = "Custom values to override Helm chart defaults"
  type        = map(string)
  default = {
    "server.service.type"                                                                = "LoadBalancer"
    "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type" = "nlb"
  }
}
