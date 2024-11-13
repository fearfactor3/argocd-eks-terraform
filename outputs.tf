output "eks_connect" {
  value = "aws eks update-kubeconfig --region us-east-1 --name ${aws_eks_cluster.main.name}"
}

output "argocd_server_load_balancer" {
  value = data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname
}

output "argocd_initial_admin_secret" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
}
