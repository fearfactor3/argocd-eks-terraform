resource "helm_release" "argocd" {
  name             = var.release_name
  repository       = var.helm_repo_url
  chart            = var.chart_name
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  dynamic "set" {
    for_each = var.values
    content {
      name  = set.key
      value = set.value
    }
  }
}

data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}