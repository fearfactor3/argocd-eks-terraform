output "prometheus_release_name" {
  value = helm_release.prometheus.name
}

output "prometheus_release_namespace" {
  value = helm_release.prometheus.namespace
}
