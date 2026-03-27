# No backend block — Spacelift injects its own state backend for all managed
# stacks. Adding a backend block here would conflict with Spacelift's state management.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = "~> 1.10"
}
