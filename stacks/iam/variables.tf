variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}

variable "github_oidc_thumbprint" {
  description = "SHA-1 thumbprint of the GitHub Actions OIDC TLS certificate. Retrieve with: openssl s_client -connect token.actions.githubusercontent.com:443 </dev/null 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | tr -d ':' | cut -d= -f2 | tr 'A-Z' 'a-z'"
  type        = string
}
