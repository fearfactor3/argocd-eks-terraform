output "prometheus_release_namespace" {
  description = "Namespace where Prometheus is installed"
  value       = module.prometheus.prometheus_release_namespace
}

output "grafana_load_balancer" {
  description = "Load balancer hostname for Grafana"
  value       = module.prometheus.grafana_load_balancer
}

output "grafana_admin_password" {
  description = "Command to retrieve the Grafana admin password"
  value       = "kubectl -n prometheus get secret prometheus-grafana -o jsonpath=\"{.data.admin-password}\" | base64 -d"
}
