module "eks_cluster" {
  source                      = "../../modules/eks"
  cluster_name                = var.cluster_name
  cluster_version             = var.cluster_version
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.subnet_ids
  node_group_desired_capacity = var.node_group_desired_capacity
  node_group_max_capacity     = var.node_group_max_capacity
  node_group_min_capacity     = var.node_group_min_capacity
  node_group_instance_types   = var.node_group_instance_types
  public_access_cidrs         = var.public_access_cidrs
  vpc_cni_addon_version       = var.vpc_cni_addon_version
  coredns_addon_version       = var.coredns_addon_version
  kube_proxy_addon_version    = var.kube_proxy_addon_version
  ebs_csi_addon_version       = var.ebs_csi_addon_version

  tags = {
    Environment = var.environment
    Team        = "DevOps"
  }
}
