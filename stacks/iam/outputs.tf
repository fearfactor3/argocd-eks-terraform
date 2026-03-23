output "github_actions_plan_role_arn" {
  description = "IAM role ARN for GitHub Actions plan workflow — set as AWS_ROLE_ARN secret in GitHub"
  value       = aws_iam_role.github_actions_plan.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
