resource "helm_release" "prometheus" {
  name             = var.release_name
  repository       = var.helm_repo_url
  chart            = var.chart_name
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  timeout = var.timeout

  dynamic "set" {
    for_each = var.values
    content {
      name  = set.key
      value = set.value
    }
  }
}

data "kubernetes_service" "prometheus_server" {
  metadata {
    name      = "prometheus-server"
    namespace = helm_release.prometheus.namespace
  }
}
