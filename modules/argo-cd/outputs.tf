output "argocd_release_name" {
  description = "Name of the Argo CD Helm release"
  value       = helm_release.argocd.name
}

output "argocd_release_namespace" {
  description = "Namespace of the Argo CD Helm release"
  value       = helm_release.argocd.namespace
}

output "argocd_server_load_balancer" {
  description = "Load balancer hostname for the Argo CD server"
  value       = try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname, "pending")
}
