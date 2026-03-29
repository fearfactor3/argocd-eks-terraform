output "argocd_release_namespace" {
  description = "Namespace where Argo CD is installed"
  value       = helm_release.argocd.namespace
}

output "argocd_server_load_balancer" {
  description = "Load balancer hostname for the Argo CD server"
  value       = try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

output "argocd_initial_admin_secret" {
  description = "Command to retrieve the Argo CD initial admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
}

output "eks_connect" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name}"
}
