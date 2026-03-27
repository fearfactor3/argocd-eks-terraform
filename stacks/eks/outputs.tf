output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks_cluster.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = module.eks_cluster.eks_cluster_endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = module.eks_cluster.eks_cluster_version
}

output "cluster_ca_certificate" {
  description = "Base64-encoded CA certificate of the EKS cluster"
  value       = module.eks_cluster.cluster_ca_certificate
  sensitive   = true
}

output "aws_lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller — consumed by the eks-addons stack"
  value       = module.eks_cluster.aws_lb_controller_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for the Cluster Autoscaler — consumed by the eks-addons stack"
  value       = module.eks_cluster.cluster_autoscaler_role_arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for the External Secrets Operator — consumed by the eks-addons stack"
  value       = module.eks_cluster.external_secrets_role_arn
}
