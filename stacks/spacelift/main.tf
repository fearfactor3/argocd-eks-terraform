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
  stack_env_vars = merge([
    for env, cfg in var.environments : {
      "network-${env}/TF_VAR_environment"             = { stack = "network-${env}", name = "TF_VAR_environment", value = env, write_only = false }
      "network-${env}/TF_VAR_vpc_cidr"                = { stack = "network-${env}", name = "TF_VAR_vpc_cidr", value = cfg.vpc_cidr, write_only = false }
      "network-${env}/TF_VAR_cluster_name"            = { stack = "network-${env}", name = "TF_VAR_cluster_name", value = cfg.cluster_name, write_only = false }
      "network-${env}/TF_VAR_public_subnets"          = { stack = "network-${env}", name = "TF_VAR_public_subnets", value = jsonencode(cfg.public_subnets), write_only = false }
      "network-${env}/TF_VAR_private_subnets"         = { stack = "network-${env}", name = "TF_VAR_private_subnets", value = jsonencode(cfg.private_subnets), write_only = false }
      "network-${env}/TF_VAR_flow_logs_traffic_type"  = { stack = "network-${env}", name = "TF_VAR_flow_logs_traffic_type", value = cfg.flow_logs_traffic_type, write_only = false }
      "eks-${env}/TF_VAR_environment"                 = { stack = "eks-${env}", name = "TF_VAR_environment", value = env, write_only = false }
      "eks-${env}/TF_VAR_cluster_name"                = { stack = "eks-${env}", name = "TF_VAR_cluster_name", value = cfg.cluster_name, write_only = false }
      "eks-${env}/TF_VAR_node_group_instance_types"   = { stack = "eks-${env}", name = "TF_VAR_node_group_instance_types", value = jsonencode(cfg.node_instance_types), write_only = false }
      "eks-${env}/TF_VAR_node_group_desired_capacity" = { stack = "eks-${env}", name = "TF_VAR_node_group_desired_capacity", value = tostring(cfg.node_desired), write_only = false }
      "eks-${env}/TF_VAR_node_group_max_capacity"     = { stack = "eks-${env}", name = "TF_VAR_node_group_max_capacity", value = tostring(cfg.node_max), write_only = false }
      "eks-${env}/TF_VAR_node_group_min_capacity"     = { stack = "eks-${env}", name = "TF_VAR_node_group_min_capacity", value = tostring(cfg.node_min), write_only = false }
      "eks-${env}/TF_VAR_node_capacity_type"          = { stack = "eks-${env}", name = "TF_VAR_node_capacity_type", value = cfg.node_capacity_type, write_only = false }
      "eks-${env}/TF_VAR_enable_scheduled_scaling"    = { stack = "eks-${env}", name = "TF_VAR_enable_scheduled_scaling", value = tostring(cfg.enable_scheduled_scaling), write_only = false }
      "eks-${env}/TF_VAR_public_access_cidrs"         = { stack = "eks-${env}", name = "TF_VAR_public_access_cidrs", value = jsonencode(cfg.public_access_cidrs), write_only = false }
      "eks-addons-${env}/TF_VAR_environment"          = { stack = "eks-addons-${env}", name = "TF_VAR_environment", value = env, write_only = false }
      "argo-cd-${env}/TF_VAR_environment"             = { stack = "argo-cd-${env}", name = "TF_VAR_environment", value = env, write_only = false }
      "argo-cd-${env}/TF_VAR_argocd_resource_profile" = { stack = "argo-cd-${env}", name = "TF_VAR_argocd_resource_profile", value = cfg.argocd_resource_profile, write_only = false }
      "argo-cd-${env}/TF_VAR_argocd_source_repo"      = { stack = "argo-cd-${env}", name = "TF_VAR_argocd_source_repo", value = cfg.argocd_source_repo, write_only = false }
      # certificate_arn is marked secret — it identifies TLS infrastructure and
      # should not be visible in Spacelift run logs or the UI.
      "argo-cd-${env}/TF_VAR_certificate_arn"            = { stack = "argo-cd-${env}", name = "TF_VAR_certificate_arn", value = cfg.certificate_arn, write_only = true }
      "prometheus-${env}/TF_VAR_environment"             = { stack = "prometheus-${env}", name = "TF_VAR_environment", value = env, write_only = false }
      "prometheus-${env}/TF_VAR_prometheus_storage_size" = { stack = "prometheus-${env}", name = "TF_VAR_prometheus_storage_size", value = cfg.prometheus_storage_size, write_only = false }
      "prometheus-${env}/TF_VAR_loki_storage_size"       = { stack = "prometheus-${env}", name = "TF_VAR_loki_storage_size", value = cfg.loki_storage_size, write_only = false }
      "prometheus-${env}/TF_VAR_certificate_arn"         = { stack = "prometheus-${env}", name = "TF_VAR_certificate_arn", value = cfg.certificate_arn, write_only = true }
    }
  ]...)
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

# Dependencies: eks depends on network, per environment
resource "spacelift_stack_dependency" "eks_needs_network" {
  for_each = var.environments

  stack_id            = spacelift_stack.env["eks-${each.key}"].id
  depends_on_stack_id = spacelift_stack.env["network-${each.key}"].id
}

# Dependencies: eks-addons depends on eks (needs cluster + LB controller role), per environment
resource "spacelift_stack_dependency" "eks_addons_needs_eks" {
  for_each = var.environments

  stack_id            = spacelift_stack.env["eks-addons-${each.key}"].id
  depends_on_stack_id = spacelift_stack.env["eks-${each.key}"].id
}

# Dependencies: argo-cd depends on eks-addons (LB controller must be running before Ingress), per environment
resource "spacelift_stack_dependency" "argo_cd_needs_eks_addons" {
  for_each = var.environments

  stack_id            = spacelift_stack.env["argo-cd-${each.key}"].id
  depends_on_stack_id = spacelift_stack.env["eks-addons-${each.key}"].id
}

# Dependencies: prometheus depends on eks-addons, per environment
resource "spacelift_stack_dependency" "prometheus_needs_eks_addons" {
  for_each            = var.environments
  stack_id            = spacelift_stack.env["prometheus-${each.key}"].id
  depends_on_stack_id = spacelift_stack.env["eks-addons-${each.key}"].id
}

# Cross-stack output references: network -> eks
resource "spacelift_stack_dependency_reference" "vpc_id" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_needs_network[each.key].id
  output_name         = "vpc_id"
  input_name          = "TF_VAR_vpc_id"
}

resource "spacelift_stack_dependency_reference" "subnet_ids" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_needs_network[each.key].id
  output_name         = "private_subnet_ids"
  input_name          = "TF_VAR_subnet_ids"
}

resource "spacelift_stack_dependency_reference" "vpc_cidr_block" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_needs_network[each.key].id
  output_name         = "vpc_cidr_block"
  input_name          = "TF_VAR_vpc_cidr_block"
}

# Cross-stack output references: eks -> eks-addons
resource "spacelift_stack_dependency_reference" "eks_addons_cluster_name" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_addons_needs_eks[each.key].id
  output_name         = "eks_cluster_name"
  input_name          = "TF_VAR_eks_cluster_name"
}

resource "spacelift_stack_dependency_reference" "eks_addons_cluster_endpoint" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_addons_needs_eks[each.key].id
  output_name         = "eks_cluster_endpoint"
  input_name          = "TF_VAR_eks_cluster_endpoint"
}

resource "spacelift_stack_dependency_reference" "eks_addons_cluster_ca_certificate" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_addons_needs_eks[each.key].id
  output_name         = "cluster_ca_certificate"
  input_name          = "TF_VAR_cluster_ca_certificate"
}

resource "spacelift_stack_dependency_reference" "eks_addons_lb_controller_role_arn" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_addons_needs_eks[each.key].id
  output_name         = "aws_lb_controller_role_arn"
  input_name          = "TF_VAR_aws_lb_controller_role_arn"
}

resource "spacelift_stack_dependency_reference" "eks_addons_cluster_autoscaler_role_arn" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_addons_needs_eks[each.key].id
  output_name         = "cluster_autoscaler_role_arn"
  input_name          = "TF_VAR_cluster_autoscaler_role_arn"
}

resource "spacelift_stack_dependency_reference" "eks_addons_external_secrets_role_arn" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.eks_addons_needs_eks[each.key].id
  output_name         = "external_secrets_role_arn"
  input_name          = "TF_VAR_external_secrets_role_arn"
}

# Cross-stack output references: eks-addons -> argo-cd
# argo-cd and prometheus now depend on eks-addons (not eks directly) so the
# LB controller is running before any Ingress resources are created.
# The cluster credentials are passed through from the eks-addons dependency.
resource "spacelift_stack_dependency_reference" "argo_cd_eks_cluster_name" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.argo_cd_needs_eks_addons[each.key].id
  output_name         = "eks_cluster_name"
  input_name          = "TF_VAR_eks_cluster_name"
}

resource "spacelift_stack_dependency_reference" "argo_cd_eks_cluster_endpoint" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.argo_cd_needs_eks_addons[each.key].id
  output_name         = "eks_cluster_endpoint"
  input_name          = "TF_VAR_eks_cluster_endpoint"
}

resource "spacelift_stack_dependency_reference" "argo_cd_cluster_ca_certificate" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.argo_cd_needs_eks_addons[each.key].id
  output_name         = "cluster_ca_certificate"
  input_name          = "TF_VAR_cluster_ca_certificate"
}

# Cross-stack output references: eks-addons -> prometheus
resource "spacelift_stack_dependency_reference" "prometheus_eks_cluster_name" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.prometheus_needs_eks_addons[each.key].id
  output_name         = "eks_cluster_name"
  input_name          = "TF_VAR_eks_cluster_name"
}

resource "spacelift_stack_dependency_reference" "prometheus_eks_cluster_endpoint" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.prometheus_needs_eks_addons[each.key].id
  output_name         = "eks_cluster_endpoint"
  input_name          = "TF_VAR_eks_cluster_endpoint"
}

resource "spacelift_stack_dependency_reference" "prometheus_cluster_ca_certificate" {
  for_each            = var.environments
  stack_dependency_id = spacelift_stack_dependency.prometheus_needs_eks_addons[each.key].id
  output_name         = "cluster_ca_certificate"
  input_name          = "TF_VAR_cluster_ca_certificate"
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
