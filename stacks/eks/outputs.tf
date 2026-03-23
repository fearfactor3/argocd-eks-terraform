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
