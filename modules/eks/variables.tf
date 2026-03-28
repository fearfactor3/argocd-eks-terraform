variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  nullable    = false
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.cluster_version))
    error_message = "cluster_version must be in the form \"1.32\"."
  }
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
  nullable    = false
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block — provide to scope the cluster SG ingress rule without a data lookup during plan"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnets for the EKS cluster"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "node_group_desired_capacity" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_desired_capacity >= var.node_group_min_capacity
    error_message = "node_group_desired_capacity must be >= node_group_min_capacity."
  }
}

variable "node_group_max_capacity" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_max_capacity >= var.node_group_desired_capacity
    error_message = "node_group_max_capacity must be >= node_group_desired_capacity."
  }
}

variable "node_group_min_capacity" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1

  validation {
    condition     = var.node_group_min_capacity >= 1
    error_message = "node_group_min_capacity must be at least 1."
  }
}

variable "node_group_instance_types" {
  description = "Instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "At least one instance type must be provided."
  }
}

variable "node_capacity_type" {
  description = "Capacity type for the node group. Use SPOT for dev to reduce EC2 costs by ~60-70%; ON_DEMAND for prod stability."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "public_access_cidrs" {
  description = "CIDR blocks permitted to reach the EKS public API endpoint"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.public_access_cidrs) > 0
    error_message = "public_access_cidrs must not be empty — provide at least one CIDR to allow EKS API access."
  }

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All public_access_cidrs must be valid CIDR blocks."
  }
}

variable "cloudwatch_log_group_arns" {
  description = "CloudWatch log group ARNs the node role may read. Provide the VPC flow logs ARN to scope to least-privilege; defaults to [\"*\"] which permits reading any log group."
  type        = list(string)
  default     = ["*"]
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

variable "enable_scheduled_scaling" {
  description = "When true, scales the node group to 0 each weekday evening and back up each morning. Reduces EC2 costs ~70% for clusters only needed during business hours (e.g. dev). Uses UTC times — adjust scale_up_cron and scale_down_cron for your timezone."
  type        = bool
  default     = false
}

variable "scale_up_cron" {
  description = "Cron expression (UTC) to scale the node group back up. Default: 08:00 Mon-Fri UTC."
  type        = string
  default     = "0 8 * * MON-FRI"
}

variable "scale_down_cron" {
  description = "Cron expression (UTC) to scale the node group to 0. Default: 20:00 Mon-Fri UTC."
  type        = string
  default     = "0 20 * * MON-FRI"
}

variable "control_plane_log_retention_days" {
  description = "Retention period in days for the EKS control plane CloudWatch log group (/aws/eks/<cluster>/cluster). AWS creates this group automatically when enabled_cluster_log_types is set but applies no expiry — without this, logs accumulate indefinitely at $0.03/GB/month."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.control_plane_log_retention_days)
    error_message = "control_plane_log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}

variable "admin_iam_principals" {
  description = "IAM principal ARNs (users or roles) granted AmazonEKSClusterAdminPolicy via access entries. Requires authentication_mode API_AND_CONFIG_MAP or API. Prefer role ARNs over user ARNs so access is revoked by removing the role assumption, not by editing this list."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.admin_iam_principals :
      can(regex("^arn:aws:iam::[0-9]{12}:(user|role|assumed-role)/.+$", arn))
    ])
    error_message = "All admin_iam_principals must be valid IAM ARNs (arn:aws:iam::{account}:{user|role|assumed-role}/{name})."
  }
}

# IRSA service account bindings — override if the Helm chart deploys with a
# non-default service account name (e.g. when using a custom values file).
variable "ebs_csi_service_account" {
  description = "Kubernetes service account name for the EBS CSI controller in kube-system"
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "aws_lb_controller_service_account" {
  description = "Kubernetes service account name for the AWS Load Balancer Controller in kube-system"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "cluster_autoscaler_service_account" {
  description = "Kubernetes service account name for the Cluster Autoscaler in kube-system"
  type        = string
  default     = "cluster-autoscaler"
}

variable "external_secrets_namespace" {
  description = "Kubernetes namespace where the External Secrets Operator is installed"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "Kubernetes service account name for the External Secrets Operator"
  type        = string
  default     = "external-secrets"
}
