output "eks_cluster_name" {
  value = module.eks_cluster.eks_cluster_name
}

output "eks_cluster_version" {
  value = module.eks_cluster.eks_cluster_version
}


output "argocd_release_namespace" {
  value = module.argo-cd.argocd_release_namespace
}

output "eks_connect" {
  value = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks_cluster.eks_cluster_name}"
}

output "argocd_initial_admin_secret" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
}

output "argocd_server_load_balancer" {
  value = module.argo-cd.argocd_server_load_balancer
}