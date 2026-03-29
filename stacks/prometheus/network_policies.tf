# Phase 1 NetworkPolicy hardening for the prometheus namespace.
#
# Design: default-deny-all + explicit allow rules. Each policy has a single
# responsibility so they can be extended or removed independently.
#
# Traffic model:
#   - ALB (IP target-type) → grafana:3000
#   - prometheus/grafana/loki/alloy ↔ intra-namespace (scraping + log push)
#   - prometheus             → kube-apiserver:443    (service discovery)
#   - prometheus             → kubelet:10250          (node metrics)
#   - prometheus             → argocd namespace       (component metrics)
#   - alloy                  → CloudWatch:443         (VPC flow log ingestion)
#   - all pods               → kube-dns:53            (DNS resolution)

resource "kubernetes_network_policy_v1" "prometheus_default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# All components in the prometheus namespace (prometheus, grafana, loki, alloy,
# alertmanager, kube-state-metrics, node-exporter) communicate freely.
resource "kubernetes_network_policy_v1" "prometheus_allow_intra" {
  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {}
      }
    }

    egress {
      to {
        pod_selector {}
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "prometheus_allow_dns" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }

      ports {
        port     = "53"
        protocol = "UDP"
      }

      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# ALB forwards traffic to grafana pod IPs directly (ip target-type).
resource "kubernetes_network_policy_v1" "prometheus_allow_alb_grafana" {
  metadata {
    name      = "allow-alb-ingress-grafana"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "grafana"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      ports {
        port     = "3000"
        protocol = "TCP"
      }
    }
  }
}

# Covers:
#   - prometheus → kube-apiserver (service discovery, component metrics)
#   - alloy      → CloudWatch Logs (VPC flow log ingestion)
resource "kubernetes_network_policy_v1" "prometheus_allow_https_egress" {
  metadata {
    name      = "allow-https-egress"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }

      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
  }
}

# node-exporter runs with hostNetwork=true so prometheus scrapes the node IP
# on port 9100. kubelet metrics are on 10250. Both targets are node IPs
# (not pod IPs) so a pod_selector cannot be used — ipBlock covers all nodes.
resource "kubernetes_network_policy_v1" "prometheus_allow_node_scrape" {
  metadata {
    name      = "allow-node-scrape-egress"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "prometheus"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }

      ports {
        port     = "9100"
        protocol = "TCP"
      }

      ports {
        port     = "10250"
        protocol = "TCP"
      }
    }
  }
}

# Prometheus scrapes Kyverno controller metrics on port 8000.
resource "kubernetes_network_policy_v1" "prometheus_allow_kyverno_scrape" {
  metadata {
    name      = "allow-kyverno-scrape-egress"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "prometheus"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kyverno"
          }
        }
      }

      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}

# Prometheus scrapes ArgoCD component metrics across namespaces.
resource "kubernetes_network_policy_v1" "prometheus_allow_argocd_scrape" {
  metadata {
    name      = "allow-argocd-scrape-egress"
    namespace = kubernetes_namespace_v1.prometheus.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "prometheus"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "argocd"
          }
        }
      }

      ports {
        port     = "8080"
        protocol = "TCP"
      }

      ports {
        port     = "8082"
        protocol = "TCP"
      }

      ports {
        port     = "8083"
        protocol = "TCP"
      }

      ports {
        port     = "8084"
        protocol = "TCP"
      }
    }
  }
}
