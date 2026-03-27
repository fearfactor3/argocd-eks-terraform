output "spacelift_integration_role_arn" {
  description = "ARN of the IAM role Spacelift assumes for plan and apply runs — use this to verify the trust relationship in the AWS console."
  value       = aws_iam_role.spacelift_integration.arn
}

output "spacelift_integration_id" {
  description = "Spacelift AWS integration ID — reference this when attaching additional stacks outside of this module."
  value       = spacelift_aws_integration.this.id
}
