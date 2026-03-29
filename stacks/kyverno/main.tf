# Namespace is managed explicitly so Pod Security Standard labels are in place
# before Helm schedules any pods. Kyverno 3.x runs fully non-root with dropped
# capabilities — restricted enforcement is correct here.
resource "kubernetes_namespace_v1" "kyverno" {
  metadata {
    name = "kyverno"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

# Kyverno core — admission controller, background controller, cleanup controller,
# and reports controller.
#
# Replica counts: dev=1 (accepted trade-off — webhook failurePolicy=Fail means
# a down pod blocks new pod scheduling in dev), prod=3 (chart PDB requires at
# least 2 Available; 3 replicas satisfy HA).
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = var.kyverno_chart_version
  namespace        = kubernetes_namespace_v1.kyverno.metadata[0].name
  create_namespace = false
  cleanup_on_fail  = true

  set = [
    # Admission controller
    {
      name  = "admissionController.replicas"
      value = var.environment == "prod" ? "3" : "1"
    },
    {
      name  = "admissionController.container.securityContext.allowPrivilegeEscalation"
      value = "false"
    },
    {
      name  = "admissionController.container.securityContext.capabilities.drop[0]"
      value = "ALL"
    },
    {
      name  = "admissionController.container.securityContext.runAsNonRoot"
      value = "true"
    },
    {
      name  = "admissionController.container.securityContext.seccompProfile.type"
      value = "RuntimeDefault"
    },
    # Background controller
    {
      name  = "backgroundController.replicas"
      value = var.environment == "prod" ? "3" : "1"
    },
    {
      name  = "backgroundController.container.securityContext.allowPrivilegeEscalation"
      value = "false"
    },
    {
      name  = "backgroundController.container.securityContext.capabilities.drop[0]"
      value = "ALL"
    },
    {
      name  = "backgroundController.container.securityContext.runAsNonRoot"
      value = "true"
    },
    {
      name  = "backgroundController.container.securityContext.seccompProfile.type"
      value = "RuntimeDefault"
    },
    # Cleanup controller
    {
      name  = "cleanupController.replicas"
      value = var.environment == "prod" ? "3" : "1"
    },
    {
      name  = "cleanupController.container.securityContext.allowPrivilegeEscalation"
      value = "false"
    },
    {
      name  = "cleanupController.container.securityContext.capabilities.drop[0]"
      value = "ALL"
    },
    {
      name  = "cleanupController.container.securityContext.runAsNonRoot"
      value = "true"
    },
    {
      name  = "cleanupController.container.securityContext.seccompProfile.type"
      value = "RuntimeDefault"
    },
    # Reports controller
    {
      name  = "reportsController.replicas"
      value = var.environment == "prod" ? "3" : "1"
    },
    {
      name  = "reportsController.container.securityContext.allowPrivilegeEscalation"
      value = "false"
    },
    {
      name  = "reportsController.container.securityContext.capabilities.drop[0]"
      value = "ALL"
    },
    {
      name  = "reportsController.container.securityContext.runAsNonRoot"
      value = "true"
    },
    {
      name  = "reportsController.container.securityContext.seccompProfile.type"
      value = "RuntimeDefault"
    },
  ]
}

# Kyverno pod security and best-practice ClusterPolicies.
#
# All policies run in Audit mode — violations are reported but no pods are
# blocked. This provides a clean signal before promoting any policy to Enforce.
#
# Known expected violations:
#   - prometheus namespace: node-exporter requires privileged capabilities and
#     will trigger disallow-privileged-containers and related policies. These
#     are non-blocking in Audit mode. Create a Kyverno PolicyException before
#     promoting those policies to Enforce.
#
# depends_on: Helm waits for kyverno pods to be Ready before marking the
# release complete, so the admission webhook is live when policies are applied.
resource "helm_release" "kyverno_policies" {
  name             = "kyverno-policies"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno-policies"
  version          = var.kyverno_policies_chart_version
  namespace        = kubernetes_namespace_v1.kyverno.metadata[0].name
  create_namespace = false
  cleanup_on_fail  = true

  depends_on = [helm_release.kyverno]

  set = [
    {
      name  = "podSecurityStandard"
      value = "baseline"
    },
    {
      name  = "validationFailureAction"
      value = "Audit"
    },
    {
      name  = "podSecurity.enabled"
      value = "true"
    },
    {
      name  = "bestPractices.enabled"
      value = "true"
    },
  ]
}
