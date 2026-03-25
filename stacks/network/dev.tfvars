environment     = "dev"
cluster_name    = "argocd-dev"
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

# REJECT reduces CloudWatch ingestion costs in dev; use ALL in prod for full visibility
flow_logs_traffic_type = "REJECT"
