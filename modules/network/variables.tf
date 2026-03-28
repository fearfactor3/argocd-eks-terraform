variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnets" {
  description = "List of CIDR blocks for the public subnets"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.public_subnets) > 0
    error_message = "At least one public subnet CIDR must be provided."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnets : can(cidrhost(cidr, 0))])
    error_message = "All public_subnets entries must be valid IPv4 CIDR blocks."
  }
}

variable "private_subnets" {
  description = "List of CIDR blocks for the private subnets"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "At least one private subnet CIDR must be provided."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnets : can(cidrhost(cidr, 0))])
    error_message = "All private_subnets entries must be valid IPv4 CIDR blocks."
  }
}

variable "azs" {
  description = "List of availability zones — must have at least as many entries as the larger of public_subnets or private_subnets"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.azs) > 0
    error_message = "At least one availability zone must be provided."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster, used for Kubernetes subnet discovery tags"
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Additional tags to apply to all network resources. Use for cost allocation (Environment, Project, ManagedBy)."
  type        = map(string)
  default     = {}
}

variable "flow_logs_traffic_type" {
  description = "VPC flow logs traffic type. Use ALL for prod (full visibility) and REJECT for dev to reduce CloudWatch ingestion costs by 60-80%."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ALL, ACCEPT, or REJECT."
  }
}

variable "flow_logs_retention_days" {
  description = "Retention period in days for the VPC flow logs CloudWatch log group. Use 7 for dev (cost savings); increase for compliance or long-term trend analysis."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a valid CloudWatch retention period."
  }
}
