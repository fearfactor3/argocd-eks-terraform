environment     = "prod"
cluster_name    = "argocd-prod"
vpc_cidr        = "10.1.0.0/16"
public_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnets = ["10.1.3.0/24", "10.1.4.0/24"]

flow_logs_traffic_type   = "ALL"
flow_logs_retention_days = 30
