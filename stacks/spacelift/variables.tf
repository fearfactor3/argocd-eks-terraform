variable "spacelift_api_url" {
  description = "Your Spacelift account URL (e.g. https://yourco.app.spacelift.io)"
  type        = string
}

variable "spacelift_api_key_id" {
  description = "Spacelift API key ID"
  type        = string
  sensitive   = true
}

variable "spacelift_api_key_secret" {
  description = "Spacelift API key secret"
  type        = string
  sensitive   = true
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

variable "branch" {
  description = "Git branch to track"
  type        = string
  default     = "main"
}

variable "opentofu_version" {
  description = "OpenTofu version for all app stacks"
  type        = string
  default     = "1.10.0"
}

variable "autodeploy" {
  description = "Whether stacks automatically apply after a successful plan"
  type        = bool
  default     = false
}
