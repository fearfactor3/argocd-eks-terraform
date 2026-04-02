# Custom ClusterPolicies fetched from nginx-kustomize-example.
#
# Source of truth: https://github.com/fearfactor3/nginx-kustomize-example
# under kyverno/policies/. Policies are defined as YAML there, tested with
# the Kyverno CLI, and applied here via yamldecode() — no duplication.
#
# To update a policy: edit the YAML in nginx-kustomize-example, merge to main,
# then run tofu apply in this stack (or let Spacelift pick up the drift).
#
# depends_on: ensures the Kyverno admission webhook is live before ClusterPolicy
# resources are applied, preventing a race condition during initial stack apply.

locals {
  policy_base_url = "https://raw.githubusercontent.com/fearfactor3/nginx-kustomize-example/main/kyverno/policies"
}

data "http" "require_image_tag" {
  url = "${local.policy_base_url}/require-image-tag.yaml"
}

data "http" "require_resource_limits" {
  url = "${local.policy_base_url}/require-resource-limits.yaml"
}

data "http" "require_non_root" {
  url = "${local.policy_base_url}/require-non-root.yaml"
}

data "http" "require_probes" {
  url = "${local.policy_base_url}/require-probes.yaml"
}

resource "kubectl_manifest" "require_image_tag" {
  yaml_body  = data.http.require_image_tag.response_body
  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "require_resource_limits" {
  yaml_body  = data.http.require_resource_limits.response_body
  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "require_non_root" {
  yaml_body  = data.http.require_non_root.response_body
  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "require_probes" {
  yaml_body  = data.http.require_probes.response_body
  depends_on = [helm_release.kyverno]
}
