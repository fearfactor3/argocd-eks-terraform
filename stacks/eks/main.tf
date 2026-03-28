data "aws_caller_identity" "current" {}

module "eks_cluster" {
  source                      = "../../modules/eks"
  cluster_name                = var.cluster_name
  cluster_version             = var.cluster_version
  vpc_id                      = var.vpc_id
  vpc_cidr_block              = var.vpc_cidr_block
  subnet_ids                  = var.subnet_ids
  node_group_desired_capacity = var.node_group_desired_capacity
  node_group_max_capacity     = var.node_group_max_capacity
  node_group_min_capacity     = var.node_group_min_capacity
  node_group_instance_types   = var.node_group_instance_types
  node_capacity_type          = var.node_capacity_type
  enable_scheduled_scaling    = var.enable_scheduled_scaling
  public_access_cidrs         = var.public_access_cidrs
  vpc_cni_addon_version       = var.vpc_cni_addon_version
  coredns_addon_version       = var.coredns_addon_version
  kube_proxy_addon_version    = var.kube_proxy_addon_version
  ebs_csi_addon_version       = var.ebs_csi_addon_version

  # Scope the node role's CloudWatch Logs read policy to the specific log group
  # created by the network stack for VPC flow logs. The wildcard default would
  # allow the node role to read any log group in the account.
  admin_iam_principals = var.admin_iam_principals

  cloudwatch_log_group_arns = [
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-logs/${var.cluster_name}",
    "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc-flow-logs/${var.cluster_name}:*",
  ]

  tags = merge(
    {
      Environment = var.environment
      Project     = var.cluster_name
      ManagedBy   = "opentofu"
    },
    var.tags
  )
}
