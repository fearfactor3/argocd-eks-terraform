# Namespace is managed explicitly so Pod Security Standard labels are in place
# before Helm schedules any pods. node-exporter requires hostNetwork/hostPID
# so enforce=restricted would block it — baseline is the appropriate enforcement
# level. warn/audit=restricted are applied unconditionally in all environments
# so hardening gaps surface in audit logs without blocking pods.
resource "kubernetes_namespace_v1" "prometheus" {
  metadata {
    name = "prometheus"
    labels = {
      # node-exporter requires hostNetwork/hostPID so enforce=restricted would
      # block it — keep baseline enforcement. warn/audit=restricted surfaces
      # hardening gaps in all environments without blocking pods.
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

locals {
  # Alloy River config: read VPC flow logs from CloudWatch and ship to Loki.
  # The log group name mirrors what the network module creates:
  #   /aws/vpc-flow-logs/<cluster_name>
  # Terraform interpolates var.eks_cluster_name and var.aws_region here;
  # the ${...} syntax inside the heredoc belongs to Terraform, not Alloy.
  alloy_config = <<-EOT
    loki.source.cloudwatch "vpc_flow_logs" {
      log_groups {
        names = ["/aws/vpc-flow-logs/${var.eks_cluster_name}"]
      }
      region        = "${var.aws_region}"
      poll_interval = "1m"
      forward_to    = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://loki:3100/loki/api/v1/push"
      }
    }
  EOT
}

# gp3 is the current-generation EBS volume type. We create this storage class
# manually rather than relying on the cluster default (gp2) because gp3 offers
# better baseline throughput at the same price. WaitForFirstConsumer delays
# provisioning until a pod is scheduled so the EBS volume is created in the
# correct availability zone — without this, volumes can end up in a different
# AZ than the pod that needs them, causing a mount failure.
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

# kube-prometheus-stack bundles Prometheus, Alertmanager, and Grafana into a
# single chart. Grafana is exposed via an NLB and backed by a persistent volume
# so dashboards survive pod restarts. The Loki datasource is pre-provisioned so
# no manual Grafana UI step is required after deployment.
module "prometheus" {
  source           = "../../modules/prometheus"
  release_name     = "prometheus"
  helm_repo_url    = "https://prometheus-community.github.io/helm-charts"
  chart_name       = "kube-prometheus-stack"
  chart_version    = var.prometheus_chart_version
  namespace        = kubernetes_namespace_v1.prometheus.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    commonLabels = {
      environment = var.environment
    }
    grafana = {
      service = {
        # ClusterIP — the ALB Ingress below terminates external traffic.
        # Switching from LoadBalancer removes the per-service NLB (~$16/month).
        type = "ClusterIP"
      }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        annotations = merge(
          {
            "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"  = "ip"
            "alb.ingress.kubernetes.io/listen-ports" = jsonencode([{ HTTP = 80 }])
          },
          var.certificate_arn != "" ? {
            "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
            "alb.ingress.kubernetes.io/listen-ports"    = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          } : {}
        )
        hosts = ["grafana.${var.environment}.internal"]
      }
      persistence = {
        enabled          = true
        storageClassName = "gp3"
      }
      # Pre-provision the Loki datasource so it is available immediately in
      # Grafana without any manual configuration. The URL uses the Kubernetes
      # service name — both Grafana and Loki are in the prometheus namespace.
      additionalDataSources = [
        {
          name      = "Loki"
          type      = "loki"
          url       = "http://loki:3100"
          access    = "proxy"
          isDefault = false
        }
      ]
    }
    prometheus = {
      prometheusSpec = {
        storageSpec = {
          # A PVC template tells the StatefulSet to create a dedicated EBS
          # volume for each Prometheus replica. 50Gi is sufficient for a test
          # instance; scale up based on scrape interval and metric cardinality.
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              resources = {
                requests = {
                  storage = var.prometheus_storage_size
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

# Loki in SingleBinary mode runs all components (ingester, querier, distributor,
# compactor) in a single pod. This is the simplest topology and appropriate for
# a test instance. For production, consider the scalable/distributed deployment
# mode backed by S3 object storage instead of the local filesystem.
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = var.loki_chart_version
  namespace        = kubernetes_namespace_v1.prometheus.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    deploymentMode = "SingleBinary"
    loki = {
      # auth_enabled = false disables Loki's multi-tenant mode. All logs are
      # written to and queried from the "fake" tenant. Enable for multi-team
      # environments where log isolation between tenants is required.
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        # Filesystem storage writes to the pod's local disk (the PVC below).
        # Suitable for a single replica — switching to S3 is required for HA
        # or distributed deployments because multiple pods cannot share a disk.
        type = "filesystem"
      }
      schemaConfig = {
        # v13 schema with tsdb index is the current recommended configuration.
        # The from date determines when this schema takes effect — it must be
        # in the past and should not be changed once data has been written.
        configs = [
          {
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index = {
              prefix = "loki_index_"
              period = "24h"
            }
          }
        ]
      }
    }
    singleBinary = {
      replicas = 1
      persistence = {
        enabled      = true
        storageClass = "gp3"
        size         = var.loki_storage_size
      }
    }
    # Disable microservice components — not used in SingleBinary mode
    backend = { replicas = 0 }
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    # Disable Memcached caches — not needed for a test instance
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    # Disable gateway — Alloy and Grafana address Loki directly on port 3100
    gateway = { enabled = false }
    commonLabels = {
      environment = var.environment
    }
  })]

  depends_on = [kubernetes_storage_class_v1.gp3]
}

# Grafana Alloy is the OpenTelemetry-compatible successor to Grafana Agent.
# It is configured via a River (.alloy) config stored in a ConfigMap. The
# config is rendered from the local.alloy_config heredoc defined above.
#
# Credentials: Alloy inherits AWS credentials from the EC2 node's instance
# profile (IMDSv2). The node role has CloudWatch Logs read permissions added
# in modules/eks/main.tf — no Kubernetes secrets or IRSA are required here.
resource "helm_release" "alloy" {
  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  version          = var.alloy_chart_version
  namespace        = kubernetes_namespace_v1.prometheus.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    alloy = {
      configMap = {
        content = local.alloy_config
      }
    }
    # Deploy as a single Deployment replica rather than the chart's default
    # DaemonSet. DaemonSet is appropriate for node-local log collection
    # (e.g. reading /var/log/pods). CloudWatch polling is centralised and
    # does not need to run on every node.
    controller = {
      type     = "deployment"
      replicas = 1
    }
    commonLabels = {
      environment = var.environment
    }
  })]

  depends_on = [helm_release.loki]
}
