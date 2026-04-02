locals {
  namespace = kubernetes_namespace_v1.kyverno.metadata[0].name

  # Replica count: dev=1 (single replica is acceptable; webhook failurePolicy=Fail
  # means a down pod blocks scheduling, but this is an accepted dev trade-off).
  # prod=3 satisfies the chart PDB which requires at least 2 Available replicas.
  replica_count = var.environment == "prod" ? 3 : 1

  # Security context applied to every Kyverno controller container. The kyverno
  # namespace enforces PSS restricted, which requires all of these fields.
  controller_security_context = {
    allowPrivilegeEscalation = false
    capabilities             = { drop = ["ALL"] }
    runAsNonRoot             = true
    seccompProfile           = { type = "RuntimeDefault" }
  }
}

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
  namespace        = local.namespace
  create_namespace = false
  cleanup_on_fail  = true

  values = [yamlencode({
    admissionController  = { replicas = local.replica_count, container = { securityContext = local.controller_security_context } }
    backgroundController = { replicas = local.replica_count, container = { securityContext = local.controller_security_context } }
    cleanupController    = { replicas = local.replica_count, container = { securityContext = local.controller_security_context } }
    reportsController    = { replicas = local.replica_count, container = { securityContext = local.controller_security_context } }
  })]
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
  namespace        = local.namespace
  create_namespace = false
  cleanup_on_fail  = true

  depends_on = [helm_release.kyverno]

  values = [yamlencode({
    podSecurityStandard     = "baseline"
    validationFailureAction = "Audit"
    podSecurity             = { enabled = true }
    bestPractices           = { enabled = true }
  })]
}
