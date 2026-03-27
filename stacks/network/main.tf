# Auto-discover available AZs in the current region when none are explicitly
# provided. Slicing to the number of subnets ensures we don't request more AZs
# than there are subnets, which would result in empty subnet slots.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = length(var.azs) > 0 ? var.azs : slice(
    data.aws_availability_zones.available.names,
    0,
    max(length(var.public_subnets), length(var.private_subnets))
  )
}

module "network" {
  source                 = "../../modules/network"
  vpc_cidr               = var.vpc_cidr
  public_subnets         = var.public_subnets
  private_subnets        = var.private_subnets
  azs                    = local.azs
  project_name           = var.project_name
  environment            = var.environment
  cluster_name           = var.cluster_name
  flow_logs_traffic_type = var.flow_logs_traffic_type
  tags                   = var.tags
}
