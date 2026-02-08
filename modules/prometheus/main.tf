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

data "kubernetes_service_v1" "prometheus_server" {
  metadata {
    name      = "prometheus-server"
    namespace = helm_release.prometheus.namespace
  }
}
