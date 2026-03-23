resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type = "gp3"
  }
}

module "prometheus" {
  source           = "../../modules/prometheus"
  release_name     = "prometheus"
  helm_repo_url    = "https://prometheus-community.github.io/helm-charts"
  chart_name       = "kube-prometheus-stack"
  chart_version    = var.prometheus_chart_version
  namespace        = "prometheus"
  create_namespace = true

  values = [yamlencode({
    grafana = {
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
        }
      }
      persistence = {
        enabled          = true
        storageClassName = "gp3"
      }
    }
    prometheus = {
      prometheusSpec = {
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              resources = {
                requests = {
                  storage = "50Gi"
                }
              }
            }
          }
        }
      }
    }
  })]

  depends_on = [kubernetes_storage_class_v1.gp3]
}
