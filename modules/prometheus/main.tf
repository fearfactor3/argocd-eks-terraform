terraform {
  required_version = "~> 1.10"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

resource "helm_release" "prometheus" {
  name             = var.release_name
  repository       = var.helm_repo_url
  chart            = var.chart_name
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  timeout = var.timeout

  values = var.values
}

data "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "${helm_release.prometheus.name}-grafana"
    namespace = helm_release.prometheus.namespace
  }
}
