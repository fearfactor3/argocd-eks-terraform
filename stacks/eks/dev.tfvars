environment              = "dev"
cluster_name             = "argocd-dev"
node_capacity_type       = "SPOT"
enable_scheduled_scaling = true
public_access_cidrs      = ["0.0.0.0/0"]

admin_iam_principals = [
  "arn:aws:iam::628743542483:role/spacelift-integration",
]
