module "network" {
  source          = "./modules/network"
  vpc_cidr        = "10.0.0.0/16"                  # CHANGE THIS
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"] # CHANGE THIS
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"] # CHANGE THIS
  azs             = ["us-east-1a", "us-east-1b"]   # CHANGE THIS
  project_name    = "argocd"
}

module "eks_cluster" {
  source                      = "./modules/eks"
  aws_region                  = "us-east-1"
  cluster_name                = "argocd-cluster"
  cluster_version             = "1.30"
  vpc_id                      = module.network.vpc_id
  subnet_ids                  = module.network.public_subnet_ids
  node_group_desired_capacity = 2
  node_group_max_capacity     = 3
  node_group_min_capacity     = 1
  node_group_instance_types   = ["t3.medium"]

  tags = {
    Environment = "Dev"
    Team        = "DevOps"
  }
}

module "argo-cd" {
  source           = "./modules/argo-cd"
  release_name     = "argocd"
  helm_repo_url    = "https://argoproj.github.io/argo-helm"
  chart_name       = "argo-cd"
  chart_version    = "7.7.1"
  namespace        = "argocd"
  create_namespace = true

  values = {
    "server.service.type"                                                                = "LoadBalancer"
    "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type" = "nlb"
  }
  depends_on = [module.eks_cluster]
}

module "prometheus" {
  source           = "./modules/prometheus"
  release_name     = "prometheus"
  helm_repo_url    = "https://prometheus-community.github.io/helm-charts"
  chart_name       = "kube-prometheus-stack"
  chart_version    = "66.2.1"
  namespace        = "prometheus"
  create_namespace = true

  values = {
    "podSecurityPolicy.enabled"       = true
    "server.persistentVolume.enabled" = true
    "grafana.service.type"            = "LoadBalancer"
    "prometheus.service.type"         = "LoadBalancer"
  }
  depends_on = [module.argo-cd]
}
