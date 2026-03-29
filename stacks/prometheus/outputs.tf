output "prometheus_release_namespace" {
  description = "Namespace where Prometheus is installed"
  value       = helm_release.prometheus.namespace
}

output "grafana_load_balancer" {
  description = "Load balancer hostname for Grafana"
  value       = try(data.kubernetes_service_v1.grafana.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

output "grafana_admin_password" {
  description = "Command to retrieve the Grafana admin password"
  value       = "kubectl -n prometheus get secret prometheus-grafana -o jsonpath=\"{.data.admin-password}\" | base64 -d"
}
