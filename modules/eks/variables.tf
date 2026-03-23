variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the EKS cluster"
  type        = list(string)
}

variable "node_group_desired_capacity" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "node_group_max_capacity" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 3
}

variable "node_group_min_capacity" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1
}

variable "node_group_instance_types" {
  description = "Instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "public_access_cidrs" {
  description = "CIDR blocks permitted to reach the EKS public API endpoint"
  type        = list(string)
}

variable "vpc_cni_addon_version" {
  description = "Version of the vpc-cni managed add-on (must be compatible with cluster_version)"
  type        = string
  default     = "v1.20.4-eksbuild.2"
}

variable "coredns_addon_version" {
  description = "Version of the coredns managed add-on (must be compatible with cluster_version)"
  type        = string
  default     = "v1.11.4-eksbuild.2"
}

variable "kube_proxy_addon_version" {
  description = "Version of the kube-proxy managed add-on (must be compatible with cluster_version)"
  type        = string
  default     = "v1.32.6-eksbuild.12"
}

variable "ebs_csi_addon_version" {
  description = "Version of the aws-ebs-csi-driver managed add-on (must be compatible with cluster_version)"
  type        = string
  default     = "v1.56.0-eksbuild.1"
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
