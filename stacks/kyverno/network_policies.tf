# NetworkPolicy hardening for the kyverno namespace.
#
# Design: default-deny-all + explicit allow rules. Each policy has a single
# responsibility so they can be extended or removed independently.
#
# Traffic model:
#   - EKS control plane → admission-controller:9443  (admission webhook)
#   - all controllers   → kube-apiserver:443          (watch/list/create resources)
#   - all pods          → kube-dns:53                 (DNS resolution)
#   - prometheus        → all controllers:8000         (metrics scrape)
#   - all controllers   ↔ intra-namespace              (inter-controller communication)

resource "kubernetes_network_policy_v1" "kyverno_default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.kyverno.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "kyverno_allow_intra" {
  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace_v1.kyverno.metadata[0].name
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

resource "kubernetes_network_policy_v1" "kyverno_allow_dns" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.kyverno.metadata[0].name
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

# EKS control plane IPs are dynamic (managed by AWS) — ipBlock 0.0.0.0/0 is
# required here since there is no fixed CIDR for the control plane.
resource "kubernetes_network_policy_v1" "kyverno_allow_webhook_ingress" {
  metadata {
    name      = "allow-webhook-ingress"
    namespace = kubernetes_namespace_v1.kyverno.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "admission-controller"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      ports {
        port     = "9443"
        protocol = "TCP"
      }
    }
  }
}

# All four controllers (admission, background, cleanup, reports) call the
# kube-apiserver to watch, list, and create Kubernetes resources.
resource "kubernetes_network_policy_v1" "kyverno_allow_apiserver_egress" {
  metadata {
    name      = "allow-apiserver-egress"
    namespace = kubernetes_namespace_v1.kyverno.metadata[0].name
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

# Prometheus scrapes Kyverno controller metrics on port 8000.
resource "kubernetes_network_policy_v1" "kyverno_allow_prometheus_scrape" {
  metadata {
    name      = "allow-prometheus-scrape"
    namespace = kubernetes_namespace_v1.kyverno.metadata[0].name
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
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}
