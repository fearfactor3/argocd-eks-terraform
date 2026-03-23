# Bootstrap note: Create this management stack manually in the Spacelift UI
# (project_root = stacks/spacelift), then apply once to provision the app stacks.

locals {
  app_stacks = {
    iam = {
      description  = "GitHub Actions OIDC provider and least-privilege plan role"
      project_root = "stacks/iam"
    }
    network = {
      description  = "VPC, subnets, and networking infrastructure"
      project_root = "stacks/network"
    }
    eks = {
      description  = "EKS cluster, node group, IAM, and add-ons"
      project_root = "stacks/eks"
    }
    argo-cd = {
      description  = "ArgoCD GitOps engine Helm release"
      project_root = "stacks/argo-cd"
    }
    prometheus = {
      description  = "Prometheus and Grafana monitoring stack Helm releases"
      project_root = "stacks/prometheus"
    }
  }
}

resource "spacelift_stack" "app" {
  for_each = local.app_stacks

  name         = each.key
  description  = each.value.description
  repository   = var.repository
  branch       = var.branch
  project_root = each.value.project_root
  space_id     = var.spacelift_space_id

  terraform_workflow_tool = "OPEN_TOFU"
  terraform_version       = var.opentofu_version
  autodeploy              = var.autodeploy
}

resource "spacelift_stack_dependency" "eks_needs_network" {
  stack_id            = spacelift_stack.app["eks"].id
  depends_on_stack_id = spacelift_stack.app["network"].id
}

resource "spacelift_stack_dependency" "argo_cd_needs_eks" {
  stack_id            = spacelift_stack.app["argo-cd"].id
  depends_on_stack_id = spacelift_stack.app["eks"].id
}

resource "spacelift_stack_dependency" "prometheus_needs_eks" {
  stack_id            = spacelift_stack.app["prometheus"].id
  depends_on_stack_id = spacelift_stack.app["eks"].id
}

resource "spacelift_stack_dependency_reference" "vpc_id" {
  stack_dependency_id = spacelift_stack_dependency.eks_needs_network.id
  output_name         = "vpc_id"
  input_name          = "TF_VAR_vpc_id"
}

resource "spacelift_stack_dependency_reference" "subnet_ids" {
  stack_dependency_id = spacelift_stack_dependency.eks_needs_network.id
  output_name         = "private_subnet_ids"
  input_name          = "TF_VAR_subnet_ids"
}

resource "spacelift_stack_dependency_reference" "argo_cd_eks_cluster_name" {
  stack_dependency_id = spacelift_stack_dependency.argo_cd_needs_eks.id
  output_name         = "eks_cluster_name"
  input_name          = "TF_VAR_eks_cluster_name"
}

resource "spacelift_stack_dependency_reference" "argo_cd_eks_cluster_endpoint" {
  stack_dependency_id = spacelift_stack_dependency.argo_cd_needs_eks.id
  output_name         = "eks_cluster_endpoint"
  input_name          = "TF_VAR_eks_cluster_endpoint"
}

resource "spacelift_stack_dependency_reference" "argo_cd_cluster_ca_certificate" {
  stack_dependency_id = spacelift_stack_dependency.argo_cd_needs_eks.id
  output_name         = "cluster_ca_certificate"
  input_name          = "TF_VAR_cluster_ca_certificate"
}

resource "spacelift_stack_dependency_reference" "prometheus_eks_cluster_name" {
  stack_dependency_id = spacelift_stack_dependency.prometheus_needs_eks.id
  output_name         = "eks_cluster_name"
  input_name          = "TF_VAR_eks_cluster_name"
}

resource "spacelift_stack_dependency_reference" "prometheus_eks_cluster_endpoint" {
  stack_dependency_id = spacelift_stack_dependency.prometheus_needs_eks.id
  output_name         = "eks_cluster_endpoint"
  input_name          = "TF_VAR_eks_cluster_endpoint"
}

resource "spacelift_stack_dependency_reference" "prometheus_cluster_ca_certificate" {
  stack_dependency_id = spacelift_stack_dependency.prometheus_needs_eks.id
  output_name         = "cluster_ca_certificate"
  input_name          = "TF_VAR_cluster_ca_certificate"
}
