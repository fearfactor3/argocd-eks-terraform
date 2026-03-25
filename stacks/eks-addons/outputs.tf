# Pass-through outputs so downstream stacks (argo-cd, prometheus) can declare
# a dependency on eks-addons and still receive cluster credentials via the
# Spacelift stack_dependency_reference mechanism.

output "eks_cluster_name" {
  description = "EKS cluster name — passed through for downstream stack dependencies"
  value       = var.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint — passed through for downstream stack dependencies"
  value       = var.eks_cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate — passed through for downstream stack dependencies"
  value       = var.cluster_ca_certificate
  sensitive   = true
}
