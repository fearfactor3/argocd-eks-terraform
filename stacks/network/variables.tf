variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "argocd"
}

variable "cluster_name" {
  description = "EKS cluster name, used for Kubernetes subnet discovery tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. \"10.0.0.0/16\")."
  }
}

variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.public_subnets : can(cidrhost(cidr, 0))])
    error_message = "All public_subnets entries must be valid IPv4 CIDR blocks."
  }
}

variable "private_subnets" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.private_subnets : can(cidrhost(cidr, 0))])
    error_message = "All private_subnets entries must be valid IPv4 CIDR blocks."
  }
}

variable "azs" {
  description = "Availability zones for subnets — leave empty to auto-discover from the region"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto all network resources. Use for cost allocation (Team, CostCenter) or compliance labels."
  type        = map(string)
  default     = {}
}

variable "flow_logs_traffic_type" {
  description = "VPC flow logs traffic type. ALL for prod (full visibility); REJECT for dev to reduce CloudWatch ingestion costs."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be \"ALL\", \"ACCEPT\", or \"REJECT\"."
  }
}
