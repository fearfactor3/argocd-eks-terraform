locals {
  # Resource presets keep the Helm values DRY while letting dev and prod differ.
  # "small" halves limits so ArgoCD fits comfortably on t3.medium nodes alongside
  # the Prometheus stack. "standard" applies production-grade sizing.
  resource_presets = {
    small = {
      server = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "250m", memory = "128Mi" }
      }
      repoServer = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
      controller = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
      applicationSet = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "250m", memory = "128Mi" }
      }
    }
    standard = {
      server = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
      repoServer = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "1", memory = "512Mi" }
      }
      controller = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { cpu = "1", memory = "1Gi" }
      }
      applicationSet = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "256Mi" }
      }
    }
  }
  resources = local.resource_presets[var.argocd_resource_profile]
}

# Namespace is managed explicitly so Pod Security Standard labels are in place
# before Helm schedules any pods. ArgoCD components run as non-root with
# dropped capabilities — enforce=restricted is applied unconditionally.
# warn/audit=restricted surface any future regressions introduced by chart
# upgrades. Helm's create_namespace is disabled so upgrades cannot overwrite
# the labels.
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      # ArgoCD components run as non-root with dropped capabilities — restricted
      # PSS is enforced unconditionally. warn/audit surface any future regressions.
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

# argocd-secret must exist before the Helm release starts. The chart's built-in
# hook job that normally generates server.secretkey runs as a pod and is blocked
# by the restricted Pod Security Standard on this namespace. Pre-creating the
# secret here removes that dependency and keeps enforce=restricted in place.
resource "random_password" "argocd_secret_key" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "argocd_secret" {
  metadata {
    name      = "argocd-secret"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    # Helm ownership labels/annotations are required so the ArgoCD chart can
    # adopt this pre-created secret rather than failing with "invalid ownership
    # metadata". Without these, Helm refuses to manage a secret it didn't create.
    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }
    annotations = {
      "meta.helm.sh/release-name"      = "argocd"
      "meta.helm.sh/release-namespace" = kubernetes_namespace_v1.argocd.metadata[0].name
    }
  }

  data = {
    "server.secretkey" = random_password.argocd_secret_key.result
  }

  depends_on = [kubernetes_namespace_v1.argocd]
}

# Argo CD is deployed as a GitOps engine — it watches a Git repository and
# continuously reconciles the cluster state to match what is declared there.
# The server is exposed via an NLB so the UI and CLI (argocd login) are
# reachable from outside the cluster without needing kubectl port-forward.
module "argo_cd" {
  source           = "../../modules/argo-cd"
  release_name     = "argocd"
  helm_repo_url    = "https://argoproj.github.io/argo-helm"
  chart_name       = "argo-cd"
  chart_version    = var.argocd_chart_version
  namespace        = kubernetes_namespace_v1.argocd.metadata[0].name
  create_namespace = false

  depends_on = [kubernetes_secret_v1.argocd_secret]

  values = [yamlencode({
    global = {
      commonLabels = {
        environment = var.environment
      }
      # Pod-level security context required for restricted PSS.
      # seccompProfile is not set by the chart by default in all versions.
      securityContext = {
        runAsNonRoot = true
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }
    }
    server = {
      service = {
        # ClusterIP — the ALB Ingress below terminates external traffic.
        # Switching from LoadBalancer removes the per-service NLB (~$16/month).
        type = "ClusterIP"
      }
      # Resource limits are driven by var.argocd_resource_profile so dev
      # (small) and prod (standard) can be sized appropriately. See locals
      # at the top of this file for preset values.
      resources = local.resources.server
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        capabilities             = { drop = ["ALL"] }
        readOnlyRootFilesystem   = false
      }
      ingress = {
        enabled          = true
        ingressClassName = "alb"
        annotations = merge(
          {
            # Route internet-facing traffic via the public subnets tagged
            # kubernetes.io/role/elb = 1 by the network module.
            "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
            "alb.ingress.kubernetes.io/target-type" = "ip"
            # ArgoCD uses gRPC on the same port. GRPC backend-protocol enables
            # HTTP/2 between the ALB and ArgoCD pods.
            "alb.ingress.kubernetes.io/backend-protocol" = "GRPC"
            "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
          },
          var.certificate_arn != null && var.certificate_arn != "" ? {
            "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
            "alb.ingress.kubernetes.io/listen-ports"    = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
            "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
          } : {}
        )
        hosts = ["argocd.${var.environment}.internal"]
      }
    }
    repoServer = {
      resources = local.resources.repoServer
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        capabilities             = { drop = ["ALL"] }
        readOnlyRootFilesystem   = false
      }
    }
    applicationSet = {
      resources = local.resources.applicationSet
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        capabilities             = { drop = ["ALL"] }
        readOnlyRootFilesystem   = false
      }
    }
    controller = {
      resources = local.resources.controller
      containerSecurityContext = {
        allowPrivilegeEscalation = false
        capabilities             = { drop = ["ALL"] }
        readOnlyRootFilesystem   = false
      }
    }
  })]
}

# The argocd-apps chart bootstraps ArgoCD AppProjects (and Applications) as a
# Helm release so they are version-controlled and applied after the ArgoCD CRDs
# exist. Using a separate Helm release avoids the plan-time CRD validation
# problem that kubernetes_manifest resources have with ArgoCD CRDs.
#
# The platform AppProject restricts:
#   - Source repos: var.argocd_source_repo (set to your app repo URL; see docs/runbooks/connect-app-repo.md)
#   - Destinations: in-cluster only (https://kubernetes.default.svc)
# This prevents a misconfigured Application from targeting an external cluster
# or pulling from an unexpected Git source.
resource "helm_release" "argocd_projects" {
  name       = "argocd-projects"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode({
    projects = [
      {
        name      = "platform"
        namespace = "argocd"
        additionalLabels = {
          environment = var.environment
        }
        spec = {
          description = "Platform applications for the ${var.environment} cluster"
          # Set var.argocd_source_repo to your app repository URL.
          # See docs/runbooks/connect-app-repo.md for the full procedure.
          sourceRepos = [var.argocd_source_repo]
          destinations = [
            {
              # In-cluster only — prevents Applications from targeting external clusters.
              server    = "https://kubernetes.default.svc"
              namespace = "*"
            }
          ]
          # Allow ArgoCD to manage cluster-scoped resources (Namespaces, CRDs, ClusterRoles).
          # Restrict to the explicit list once the workload set is stable.
          clusterResourceWhitelist = [
            { group = "*", kind = "*" }
          ]
          orphanedResources = {
            # Warn (not fail) when resources exist in the cluster that are not
            # tracked by any Application in this project.
            warn = true
          }
        }
      }
    ]
  })]

  depends_on = [module.argo_cd]
}
