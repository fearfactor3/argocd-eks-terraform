variable "spacelift_account_id" {
  description = "AWS account ID that Spacelift uses to assume the integration role (visible in Spacelift UI → Integrations → Trust relationship)"
  type        = string
}

variable "spacelift_org_name" {
  description = "Spacelift organization name — used as the ExternalId prefix in the trust policy (e.g. 'fearfactor3' for fearfactor3.app.spacelift.io)"
  type        = string
}

variable "spacelift_space_id" {
  description = "Spacelift space to create stacks in (use 'root' for the default space)"
  type        = string
  default     = "root"
}

variable "repository" {
  description = "GitHub repository name (e.g. argocd-eks-terraform)"
  type        = string
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repository — injected into the iam stack to scope the OIDC trust policy"
  type        = string
}

variable "github_oidc_thumbprint" {
  description = "SHA-1 thumbprint of the GitHub Actions OIDC TLS certificate — injected into the iam stack"
  type        = string
}

variable "branch" {
  description = "Git branch to track"
  type        = string
  default     = "main"
}

variable "opentofu_version" {
  description = "OpenTofu version for all app stacks"
  type        = string
  default     = "1.10.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.opentofu_version))
    error_message = "opentofu_version must be a semver string (e.g. \"1.10.0\")."
  }
}

variable "iam_propagation_seconds" {
  description = "Seconds to wait after creating the Spacelift IAM role before attaching it. IAM is eventually consistent — reduce only if your account propagates faster than the default."
  type        = number
  default     = 30
}

variable "autodeploy" {
  description = "Whether stacks automatically apply after a successful plan"
  type        = bool
  default     = false
}

variable "environments" {
  description = "Per environment configuration for network, EKS sizing, and workload hardening"
  type = map(object({
    # Network
    vpc_cidr        = string
    public_subnets  = list(string)
    private_subnets = list(string)
    # flow_logs_traffic_type: REJECT for dev reduces CloudWatch ingestion ~60-80%;
    # ALL for prod ensures full visibility into accepted + rejected traffic.
    flow_logs_traffic_type = string

    # EKS
    cluster_name        = string
    node_instance_types = list(string)
    node_desired        = number
    node_max            = number
    node_min            = number
    # node_capacity_type controls EC2 purchasing model for the node group.
    # SPOT cuts dev EC2 costs by ~60-70% with a 2-minute interruption notice.
    # ON_DEMAND for prod ensures workload stability.
    node_capacity_type = string
    # enable_scheduled_scaling scales dev to 0 each weekday evening (20:00 UTC)
    # and restores it each morning (08:00 UTC), saving ~70% of overnight EC2 cost.
    enable_scheduled_scaling = bool
    autodeploy               = bool
    # public_access_cidrs restricts which IPs may reach the EKS public API endpoint.
    # Use ["0.0.0.0/0"] for open access; tighten to known office/VPN CIDRs for prod.
    public_access_cidrs = list(string)

    # ArgoCD
    # argocd_resource_profile controls pod resource requests/limits:
    #   "small"    — halved limits, suitable for t3.medium dev nodes
    #   "standard" — production-grade limits
    argocd_resource_profile = string
    # argocd_source_repo restricts which Git repos ArgoCD may sync from.
    # Set to the app repo URL once ADR-006 is resolved; "*" allows any repo.
    argocd_source_repo = string

    # Prometheus / Loki storage
    # Smaller sizes for dev reduce gp3 EBS cost ($0.08/GB/month).
    prometheus_storage_size = string
    loki_storage_size       = string

    # TLS — set to the ACM wildcard certificate ARN for the environment's
    # domain once a Route 53 hosted zone and ACM certificate are provisioned.
    # Leave empty ("") for HTTP-only (default homelab behaviour).
    certificate_arn = string
  }))
  default = {
    dev = {
      vpc_cidr                 = "10.0.0.0/16"
      public_subnets           = ["10.0.1.0/24", "10.0.2.0/24"]
      private_subnets          = ["10.0.3.0/24", "10.0.4.0/24"]
      flow_logs_traffic_type   = "REJECT"
      cluster_name             = "argocd-dev"
      node_instance_types      = ["t3.medium"]
      node_desired             = 1
      node_max                 = 3
      node_min                 = 1
      node_capacity_type       = "SPOT"
      enable_scheduled_scaling = true
      autodeploy               = true
      public_access_cidrs      = ["0.0.0.0/0"]

      argocd_resource_profile = "small"
      argocd_source_repo      = "*"
      prometheus_storage_size = "10Gi"
      loki_storage_size       = "5Gi"
      certificate_arn         = ""
    }
    prod = {
      vpc_cidr                 = "10.1.0.0/16"
      public_subnets           = ["10.1.1.0/24", "10.1.2.0/24"]
      private_subnets          = ["10.1.3.0/24", "10.1.4.0/24"]
      flow_logs_traffic_type   = "ALL"
      cluster_name             = "argocd-prod"
      node_instance_types      = ["t3.large"]
      node_desired             = 3
      node_max                 = 6
      node_min                 = 2
      node_capacity_type       = "ON_DEMAND"
      enable_scheduled_scaling = false
      autodeploy               = false
      public_access_cidrs      = ["0.0.0.0/0"]

      argocd_resource_profile = "standard"
      argocd_source_repo      = "*"
      prometheus_storage_size = "50Gi"
      loki_storage_size       = "10Gi"
      certificate_arn         = ""
    }
  }
}
