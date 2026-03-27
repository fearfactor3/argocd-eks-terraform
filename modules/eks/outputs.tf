output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_ca_certificate" {
  description = "The EKS cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "aws_lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller IRSA — annotate the kube-system/aws-load-balancer-controller service account with this ARN."
  value       = aws_iam_role.aws_lb_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for the Cluster Autoscaler IRSA — consumed by the eks-addons stack."
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for the External Secrets Operator IRSA — consumed by the eks-addons stack."
  value       = aws_iam_role.external_secrets.arn
}
