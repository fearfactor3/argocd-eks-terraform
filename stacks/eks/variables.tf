variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "node_group_desired_capacity" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_group_max_capacity" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "node_group_min_capacity" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_group_instance_types" {
  description = "Instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for the node group. SPOT for dev (~60-70% cheaper); ON_DEMAND for prod."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "enable_scheduled_scaling" {
  description = "Scale node group to 0 each weekday evening and restore each morning. Reduces EC2 costs ~70% for dev clusters."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks permitted to reach the EKS public API endpoint"
  type        = list(string)
}

variable "vpc_cni_addon_version" {
  description = "Version of the vpc-cni managed add-on"
  type        = string
  default     = "v1.20.4-eksbuild.2"
}

variable "coredns_addon_version" {
  description = "Version of the coredns managed add-on"
  type        = string
  default     = "v1.11.4-eksbuild.2"
}

variable "kube_proxy_addon_version" {
  description = "Version of the kube-proxy managed add-on"
  type        = string
  default     = "v1.32.6-eksbuild.12"
}

variable "ebs_csi_addon_version" {
  description = "Version of the aws-ebs-csi-driver managed add-on"
  type        = string
  default     = "v1.56.0-eksbuild.1"
}

variable "tags" {
  description = "Additional tags merged onto all resources. Use for cost allocation (Team, CostCenter) or compliance labels."
  type        = map(string)
  default     = {}
}

# Cross-stack inputs from the network stack (injected by Spacelift as TF_VAR_*)
variable "vpc_id" {
  description = "VPC ID from the network stack"
  type        = string
  nullable    = false
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block from the network stack — scopes the EKS cluster SG ingress rule without a data lookup"
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "Private subnet IDs from the network stack"
  type        = list(string)
  nullable    = false
}
