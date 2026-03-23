module "argo_cd" {
  source           = "../../modules/argo-cd"
  release_name     = "argocd"
  helm_repo_url    = "https://argoproj.github.io/argo-helm"
  chart_name       = "argo-cd"
  chart_version    = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    server = {
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
        }
      }
    }
  })]
}
