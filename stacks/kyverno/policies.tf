locals {
  # Audit in dev so violations are visible without blocking workloads during
  # initial rollout. Enforce in prod once teams have had time to comply.
  validation_failure_action = var.environment == "prod" ? "Enforce" : "Audit"
}

# ClusterPolicies are applied after Kyverno is fully deployed so the admission
# webhook is live before any policy resource is created.
resource "kubectl_manifest" "policies" {
  for_each = fileset("${path.module}/policies", "*.yaml")
  yaml_body = templatefile("${path.module}/policies/${each.value}", {
    validation_failure_action = local.validation_failure_action
  })
  depends_on = [helm_release.kyverno]
}
