# Bootstrap note: see docs/bootstrap.md for the full first-time setup procedure.
#
# Summary: create this stack manually in the Spacelift UI (project_root =
# stacks/spacelift, Administrative = enabled), then run the first apply locally:
#
#   export SPACELIFT_API_KEY_ENDPOINT=https://<org>.app.spacelift.io
#   export SPACELIFT_API_KEY_ID=<key-id>
#   export SPACELIFT_API_KEY_SECRET=<key-secret>
#
#   cd stacks/spacelift
#   tofu init
#   tofu apply -var="repository=argocd-eks-terraform"
#
# Upload the resulting state to Spacelift so subsequent runs are consistent:
#
#   spacectl stack state upload -id argocd-eks-terraform < terraform.tfstate
#   rm terraform.tfstate terraform.tfstate.backup
#
# All subsequent runs are driven by Spacelift on merge to main.

data "aws_caller_identity" "current" {}

# Cross-account role that Spacelift assumes when running any attached stack.
# Trust policy values (account ID and ExternalId pattern) are sourced from
# var.spacelift_account_id and var.spacelift_org_name — visible in the Spacelift
# UI under Integrations → spacelift → Trust relationship.
resource "spacelift_aws_integration" "this" {
  name     = "spacelift"
  role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/spacelift-integration"
}

resource "aws_iam_role" "spacelift_integration" {
  name        = "spacelift-integration"
  description = "Assumed by Spacelift for plan and apply runs across all stacks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.spacelift_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringLike = {
          "sts:ExternalId" = "${var.spacelift_org_name}@*"
        }
      }
    }]
  })
}

# AdministratorAccess is intentional for this bootstrap role. Spacelift needs
# broad permissions to create and manage all stack resources (VPC, EKS, IAM
# roles, Helm releases). Scoping this down requires enumerating every action
# across every provider used by every stack — a maintenance burden that is
# disproportionate for a homelab environment where the blast radius is bounded
# to a single AWS account. Revisit with a least-privilege policy document when
# promoting to a production multi-account setup.
resource "aws_iam_role_policy_attachment" "spacelift_integration" {
  role       = aws_iam_role.spacelift_integration.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# IAM is eventually consistent — wait for the role and policy to propagate
# globally before Spacelift attempts to assume the role during attachment.
resource "time_sleep" "iam_propagation" {
  create_duration = "${var.iam_propagation_seconds}s"
  depends_on      = [aws_iam_role_policy_attachment.spacelift_integration]
}

# Attach the integration to every app stack so they receive AWS credentials.
resource "spacelift_aws_integration_attachment" "env" {
  for_each = local.env_stacks

  integration_id = spacelift_aws_integration.this.id
  stack_id       = spacelift_stack.env[each.key].id
  read           = true
  write          = true

  # Spacelift validates the trust relationship at attachment time, so the IAM
  # role and its policy must exist before any attachment is attempted.
  depends_on = [time_sleep.iam_propagation]
}

resource "spacelift_aws_integration_attachment" "iam" {
  integration_id = spacelift_aws_integration.this.id
  stack_id       = spacelift_stack.iam.id
  read           = true
  write          = true

  depends_on = [time_sleep.iam_propagation]
}

# Variables injected into the IAM stack — not per-environment so managed separately
# from stack_env_vars which only targets spacelift_stack.env stacks.
resource "spacelift_environment_variable" "iam_config" {
  for_each = {
    TF_VAR_github_org             = { value = var.github_org, write_only = false }
    TF_VAR_github_repo            = { value = var.repository, write_only = false }
    TF_VAR_github_oidc_thumbprint = { value = var.github_oidc_thumbprint, write_only = true }
  }

  stack_id   = spacelift_stack.iam.id
  name       = each.key
  value      = each.value.value
  write_only = each.value.write_only
}

locals {
  env_stack_types = {
    network = {
      description  = "VPC, subnets, and networking infrastructure"
      project_root = "stacks/network"
      # Also watch the network module — changes there affect this stack
      # but fall outside project_root so Spacelift wouldn't detect them otherwise.
      extra_globs = ["modules/network/**/*"]
    }
    eks = {
      description  = "EKS cluster, node group, IAM, and add-ons"
      project_root = "stacks/eks"
      # Also watch the eks module — changes there affect this stack.
      extra_globs = ["modules/eks/**/*"]
    }
    eks-addons = {
      description  = "AWS Load Balancer Controller and other cluster-level Helm add-ons"
      project_root = "stacks/eks-addons"
      extra_globs  = []
    }
    kyverno = {
      description  = "Kyverno policy engine and best-practice ClusterPolicies"
      project_root = "stacks/kyverno"
      extra_globs  = []
    }
    argo-cd = {
      description  = "ArgoCD GitOps engine Helm release"
      project_root = "stacks/argo-cd"
      extra_globs  = []
    }
    prometheus = {
      description  = "Prometheus and Grafana monitoring stack Helm releases"
      project_root = "stacks/prometheus"
      extra_globs  = []
    }
  }

  # Cross product of environments x stack types, keyed as "<stack>-<env>"
  env_stacks = {
    for pair in setproduct(keys(var.environments), keys(local.env_stack_types)) :
    "${pair[1]}-${pair[0]}" => {
      env          = pair[0]
      stack_type   = pair[1]
      description  = "${local.env_stack_types[pair[1]].description} (${pair[0]})"
      project_root = local.env_stack_types[pair[1]].project_root
      # Only watch module directories for non-prod environments.
      # Prod stacks trigger on explicit stack code changes (project_root) only,
      # preventing iterative dev/module work from queuing unwanted prod runs.
      extra_globs = pair[0] == "prod" ? [] : local.env_stack_types[pair[1]].extra_globs
    }
  }

  # Per-environment variables injected into each stack via spacelift_environment_variable
  stack_env_vars = merge(
    # Per-stack TF_VAR_* — dynamic values that differ per stack or environment.
    merge([
      for env, cfg in var.environments : {
        "network-${env}/TF_VAR_environment"              = { stack = "network-${env}", name = "TF_VAR_environment", value = env, write_only = false }
        "network-${env}/TF_VAR_vpc_cidr"                 = { stack = "network-${env}", name = "TF_VAR_vpc_cidr", value = cfg.vpc_cidr, write_only = false }
        "network-${env}/TF_VAR_cluster_name"             = { stack = "network-${env}", name = "TF_VAR_cluster_name", value = cfg.cluster_name, write_only = false }
        "network-${env}/TF_VAR_public_subnets"           = { stack = "network-${env}", name = "TF_VAR_public_subnets", value = jsonencode(cfg.public_subnets), write_only = false }
        "network-${env}/TF_VAR_private_subnets"          = { stack = "network-${env}", name = "TF_VAR_private_subnets", value = jsonencode(cfg.private_subnets), write_only = false }
        "network-${env}/TF_VAR_flow_logs_traffic_type"   = { stack = "network-${env}", name = "TF_VAR_flow_logs_traffic_type", value = cfg.flow_logs_traffic_type, write_only = false }
        "network-${env}/TF_VAR_flow_logs_retention_days" = { stack = "network-${env}", name = "TF_VAR_flow_logs_retention_days", value = tostring(cfg.flow_logs_retention_days), write_only = false }
        "eks-${env}/TF_VAR_environment"                  = { stack = "eks-${env}", name = "TF_VAR_environment", value = env, write_only = false }
        "eks-${env}/TF_VAR_cluster_name"                 = { stack = "eks-${env}", name = "TF_VAR_cluster_name", value = cfg.cluster_name, write_only = false }
        "eks-${env}/TF_VAR_node_group_instance_types"    = { stack = "eks-${env}", name = "TF_VAR_node_group_instance_types", value = jsonencode(cfg.node_instance_types), write_only = false }
        "eks-${env}/TF_VAR_node_group_desired_capacity"  = { stack = "eks-${env}", name = "TF_VAR_node_group_desired_capacity", value = tostring(cfg.node_desired), write_only = false }
        "eks-${env}/TF_VAR_node_group_max_capacity"      = { stack = "eks-${env}", name = "TF_VAR_node_group_max_capacity", value = tostring(cfg.node_max), write_only = false }
        "eks-${env}/TF_VAR_node_group_min_capacity"      = { stack = "eks-${env}", name = "TF_VAR_node_group_min_capacity", value = tostring(cfg.node_min), write_only = false }
        "eks-${env}/TF_VAR_node_capacity_type"           = { stack = "eks-${env}", name = "TF_VAR_node_capacity_type", value = cfg.node_capacity_type, write_only = false }
        "eks-${env}/TF_VAR_enable_scheduled_scaling"     = { stack = "eks-${env}", name = "TF_VAR_enable_scheduled_scaling", value = tostring(cfg.enable_scheduled_scaling), write_only = false }
        "eks-${env}/TF_VAR_public_access_cidrs"          = { stack = "eks-${env}", name = "TF_VAR_public_access_cidrs", value = jsonencode(cfg.public_access_cidrs), write_only = false }
        "eks-addons-${env}/TF_VAR_environment"           = { stack = "eks-addons-${env}", name = "TF_VAR_environment", value = env, write_only = false }
        "kyverno-${env}/TF_VAR_environment"              = { stack = "kyverno-${env}", name = "TF_VAR_environment", value = env, write_only = false }
        "argo-cd-${env}/TF_VAR_environment"              = { stack = "argo-cd-${env}", name = "TF_VAR_environment", value = env, write_only = false }
        "argo-cd-${env}/TF_VAR_argocd_resource_profile"  = { stack = "argo-cd-${env}", name = "TF_VAR_argocd_resource_profile", value = cfg.argocd_resource_profile, write_only = false }
        "argo-cd-${env}/TF_VAR_argocd_source_repo"       = { stack = "argo-cd-${env}", name = "TF_VAR_argocd_source_repo", value = cfg.argocd_source_repo, write_only = false }
        # certificate_arn is marked secret — it identifies TLS infrastructure and
        # should not be visible in Spacelift run logs or the UI.
        "argo-cd-${env}/TF_VAR_certificate_arn"            = { stack = "argo-cd-${env}", name = "TF_VAR_certificate_arn", value = cfg.certificate_arn, write_only = true }
        "prometheus-${env}/TF_VAR_environment"             = { stack = "prometheus-${env}", name = "TF_VAR_environment", value = env, write_only = false }
        "prometheus-${env}/TF_VAR_prometheus_storage_size" = { stack = "prometheus-${env}", name = "TF_VAR_prometheus_storage_size", value = cfg.prometheus_storage_size, write_only = false }
        "prometheus-${env}/TF_VAR_loki_storage_size"       = { stack = "prometheus-${env}", name = "TF_VAR_loki_storage_size", value = cfg.loki_storage_size, write_only = false }
        "prometheus-${env}/TF_VAR_certificate_arn"         = { stack = "prometheus-${env}", name = "TF_VAR_certificate_arn", value = cfg.certificate_arn, write_only = true }
      }
    ]...),
    # Load {env}.tfvars on every plan and apply for all env stacks. Spacelift does not
    # auto-load *.tfvars files — without this, variables like admin_iam_principals default
    # to [] and the Spacelift integration role never receives EKS cluster admin access,
    # causing all downstream kubernetes/helm provider stacks to fail authorization.
    # TF_VAR_* cross-stack injections are unaffected: they target variables absent from
    # the tfvars files so there is no precedence conflict.
    { for pair in setproduct(keys(var.environments), keys(local.env_stack_types), ["TF_CLI_ARGS_plan", "TF_CLI_ARGS_apply"]) :
      "${pair[1]}-${pair[0]}/${pair[2]}" => {
        stack      = "${pair[1]}-${pair[0]}"
        name       = pair[2]
        value      = "-var-file=${pair[0]}.tfvars"
        write_only = false
      }
    }
  )

  # Directed dependency graph: key = downstream stack, depends_on_stack = upstream.
  # Deployment order: network → eks → eks-addons → kyverno → {argo-cd, prometheus}
  stack_deps = {
    "eks"        = { stack = "eks", depends_on_stack = "network" }
    "eks-addons" = { stack = "eks-addons", depends_on_stack = "eks" }
    "kyverno"    = { stack = "kyverno", depends_on_stack = "eks-addons" }
    "argo-cd"    = { stack = "argo-cd", depends_on_stack = "kyverno" }
    "prometheus" = { stack = "prometheus", depends_on_stack = "kyverno" }
  }

  # Cross-stack output → TF_VAR_* input mappings, keyed by the downstream stack name.
  # Each entry causes Spacelift to inject one upstream output as a variable into the
  # downstream stack after the dependency run completes.
  stack_output_refs = [
    # network → eks
    { dep = "eks", output = "vpc_id", input = "TF_VAR_vpc_id" },
    { dep = "eks", output = "private_subnet_ids", input = "TF_VAR_subnet_ids" },
    { dep = "eks", output = "vpc_cidr_block", input = "TF_VAR_vpc_cidr_block" },
    # eks → eks-addons
    { dep = "eks-addons", output = "vpc_id", input = "TF_VAR_vpc_id" },
    { dep = "eks-addons", output = "eks_cluster_name", input = "TF_VAR_eks_cluster_name" },
    { dep = "eks-addons", output = "eks_cluster_endpoint", input = "TF_VAR_eks_cluster_endpoint" },
    { dep = "eks-addons", output = "cluster_ca_certificate", input = "TF_VAR_cluster_ca_certificate" },
    { dep = "eks-addons", output = "aws_lb_controller_role_arn", input = "TF_VAR_aws_lb_controller_role_arn" },
    { dep = "eks-addons", output = "cluster_autoscaler_role_arn", input = "TF_VAR_cluster_autoscaler_role_arn" },
    { dep = "eks-addons", output = "external_secrets_role_arn", input = "TF_VAR_external_secrets_role_arn" },
    # eks-addons → kyverno
    { dep = "kyverno", output = "eks_cluster_name", input = "TF_VAR_eks_cluster_name" },
    { dep = "kyverno", output = "eks_cluster_endpoint", input = "TF_VAR_eks_cluster_endpoint" },
    { dep = "kyverno", output = "cluster_ca_certificate", input = "TF_VAR_cluster_ca_certificate" },
    # kyverno → argo-cd (cluster credentials pass through kyverno as outputs)
    { dep = "argo-cd", output = "eks_cluster_name", input = "TF_VAR_eks_cluster_name" },
    { dep = "argo-cd", output = "eks_cluster_endpoint", input = "TF_VAR_eks_cluster_endpoint" },
    { dep = "argo-cd", output = "cluster_ca_certificate", input = "TF_VAR_cluster_ca_certificate" },
    # kyverno → prometheus
    { dep = "prometheus", output = "eks_cluster_name", input = "TF_VAR_eks_cluster_name" },
    { dep = "prometheus", output = "eks_cluster_endpoint", input = "TF_VAR_eks_cluster_endpoint" },
    { dep = "prometheus", output = "cluster_ca_certificate", input = "TF_VAR_cluster_ca_certificate" },
  ]
}

# IAM stack — account-scoped singleton, not per environment
resource "spacelift_stack" "iam" {
  name         = "iam"
  description  = "GitHub Actions OIDC provider and least-privilege plan role"
  repository   = var.repository
  branch       = var.branch
  project_root = "stacks/iam"
  space_id     = var.spacelift_space_id

  terraform_workflow_tool = "OPEN_TOFU"
  terraform_version       = var.opentofu_version
  autodeploy              = var.autodeploy

  labels = ["component:iam", "managed-by:opentofu"]
}

# App stacks — one per environment per stack type
resource "spacelift_stack" "env" {
  for_each = local.env_stacks

  name                     = each.key
  description              = each.value.description
  repository               = var.repository
  branch                   = var.branch
  project_root             = each.value.project_root
  additional_project_globs = each.value.extra_globs
  space_id                 = var.spacelift_space_id

  terraform_workflow_tool = "OPEN_TOFU"
  terraform_version       = var.opentofu_version
  autodeploy              = var.environments[each.value.env].autodeploy

  labels = [
    "env:${each.value.env}",
    "component:${each.value.stack_type}",
    "managed-by:opentofu",
  ]
}

# Per-environment variables injected into stacks
resource "spacelift_environment_variable" "env_config" {
  for_each = local.stack_env_vars

  stack_id   = spacelift_stack.env[each.value.stack].id
  name       = each.value.name
  value      = each.value.value
  write_only = each.value.write_only
}

# Stack dependency chain — data-driven from local.stack_deps.
# Adding a new stack only requires a new entry in the locals map, not a new resource block.
# Deployment order: network → eks → eks-addons → kyverno → {argo-cd, prometheus}
resource "spacelift_stack_dependency" "this" {
  for_each = {
    for pair in setproduct(keys(var.environments), keys(local.stack_deps)) :
    "${pair[1]}-${pair[0]}" => {
      env              = pair[0]
      stack            = local.stack_deps[pair[1]].stack
      depends_on_stack = local.stack_deps[pair[1]].depends_on_stack
    }
  }

  stack_id            = spacelift_stack.env["${each.value.stack}-${each.value.env}"].id
  depends_on_stack_id = spacelift_stack.env["${each.value.depends_on_stack}-${each.value.env}"].id
}

# Cross-stack output references — data-driven from local.stack_output_refs.
# Each entry injects one upstream output as a TF_VAR_* into the downstream stack.
# Adding a new cross-stack reference only requires a new entry in the locals list.
resource "spacelift_stack_dependency_reference" "this" {
  for_each = {
    for pair in setproduct(keys(var.environments), local.stack_output_refs) :
    "${pair[1].dep}-${pair[0]}/${pair[1].output}" => {
      env    = pair[0]
      dep    = pair[1].dep
      output = pair[1].output
      input  = pair[1].input
    }
  }

  stack_dependency_id = spacelift_stack_dependency.this["${each.value.dep}-${each.value.env}"].id
  output_name         = each.value.output
  input_name          = each.value.input
}

# Dev plan policy — warn-only, no hard blocks.
resource "spacelift_policy" "dev_plan" {
  name = "dev-plan"
  type = "PLAN"
  body = file("${path.module}/policies/dev-plan.rego")
}

resource "spacelift_policy_attachment" "dev_plan" {
  for_each  = { for k, v in local.env_stacks : k => v if v.env == "dev" }
  policy_id = spacelift_policy.dev_plan.id
  stack_id  = spacelift_stack.env[each.key].id
}

# Production plan policy — blocks destruction of protected resources.
# Destruction can only proceed when a run is triggered with the emergency override
# metadata flag. See docs/runbooks/emergency-destroy.md for the full procedure.
resource "spacelift_policy" "prod_plan" {
  name = "prod-plan"
  type = "PLAN"
  body = file("${path.module}/policies/prod-plan.rego")
}

resource "spacelift_policy_attachment" "prod_plan" {
  for_each  = { for k, v in local.env_stacks : k => v if v.env == "prod" }
  policy_id = spacelift_policy.prod_plan.id
  stack_id  = spacelift_stack.env[each.key].id
}

# Production approval policy — every tracked run requires explicit approval before
# applying. Emergency destruction runs require 2 approvals.
resource "spacelift_policy" "prod_approval" {
  name = "prod-approval"
  type = "APPROVAL"
  body = file("${path.module}/policies/prod-approval.rego")
}

resource "spacelift_policy_attachment" "prod_approval" {
  for_each  = { for k, v in local.env_stacks : k => v if v.env == "prod" }
  policy_id = spacelift_policy.prod_approval.id
  stack_id  = spacelift_stack.env[each.key].id
}
