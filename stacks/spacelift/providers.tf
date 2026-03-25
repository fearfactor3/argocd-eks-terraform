provider "aws" {
  region = "us-east-1"
}

# When running inside a Spacelift run the provider auto-configures from the
# injected SPACELIFT_API_KEY_ENDPOINT / _ID / _SECRET environment variables.
# No explicit credentials needed here.
provider "spacelift" {}
