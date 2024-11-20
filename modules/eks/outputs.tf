output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.version
}

output "cluster_ca_certificate" {
  description = "The EKS cluster CA certificate"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}
