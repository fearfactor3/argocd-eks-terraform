# No backend block — Spacelift injects its own state backend for all managed
# stacks. Adding a backend block here would conflict with Spacelift's state
# management. The spacelift stack itself bootstraps locally (see docs/bootstrap.md).
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
  required_version = "~> 1.10"
}
