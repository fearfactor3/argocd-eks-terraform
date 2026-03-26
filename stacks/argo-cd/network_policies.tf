# Phase 1 NetworkPolicy hardening for the argocd namespace.
#
# Design: default-deny-all + explicit allow rules. Each policy has a single
# responsibility so they can be extended or removed independently.
#
# Traffic model:
#   - ALB (IP target-type) → argocd-server:8080
#   - argocd components    ↔ argocd components  (intra-namespace)
#   - argocd pods          → kube-apiserver:443  (application-controller)
#   - argocd repo-server   → GitHub/Git:443       (manifest pulls)
#   - prometheus namespace → argocd metrics ports (scraping)
#   - all pods             → kube-dns:53          (DNS resolution)

resource "kubernetes_network_policy_v1" "argocd_default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# ArgoCD components (server, repo-server, application-controller, redis,
# applicationset-controller, dex) communicate freely within the namespace.
resource "kubernetes_network_policy_v1" "argocd_allow_intra" {
  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
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

resource "kubernetes_network_policy_v1" "argocd_allow_dns" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
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

# ALB forwards traffic to pod IPs directly (ip target-type). The source is a
# VPC-internal IP — no namespace selector applies. Port 8080 is the only
# argocd-server listener; the ALB handles TLS termination.
resource "kubernetes_network_policy_v1" "argocd_allow_alb" {
  metadata {
    name      = "allow-alb-ingress"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-server"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

# application-controller needs the kube-apiserver for watch/list operations.
# repo-server needs HTTPS for manifest pulls from Git.
# Both are covered by allowing egress on port 443 to any destination.
resource "kubernetes_network_policy_v1" "argocd_allow_https_egress" {
  metadata {
    name      = "allow-https-egress"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
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

# Allow Prometheus to scrape ArgoCD component metrics.
# Ports: 8082 (application-controller), 8083 (server metrics),
#        8084 (repo-server metrics), 8080 (applicationset-controller).
resource "kubernetes_network_policy_v1" "argocd_allow_prometheus_scrape" {
  metadata {
    name      = "allow-prometheus-scrape"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "prometheus"
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
