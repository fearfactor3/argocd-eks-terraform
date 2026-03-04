output "prometheus_release_name" {
  value = helm_release.prometheus.name
}

output "prometheus_release_namespace" {
  value = helm_release.prometheus.namespace
}

output "grafana_load_balancer" {
  description = "Load balancer hostname for Grafana"
  value       = try(data.kubernetes_service_v1.grafana.status.0.load_balancer.0.ingress.0.hostname, "pending")
}
