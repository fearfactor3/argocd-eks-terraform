module "network" {
  source          = "./modules/network"
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  azs             = var.azs
  project_name    = var.project_name
}

module "eks_cluster" {
  source                      = "./modules/eks"
  cluster_name                = var.cluster_name
  cluster_version             = var.cluster_version
  vpc_id                      = module.network.vpc_id
  subnet_ids                  = module.network.private_subnet_ids
  node_group_desired_capacity = var.node_group_desired_capacity
  node_group_max_capacity     = var.node_group_max_capacity
  node_group_min_capacity     = var.node_group_min_capacity
  node_group_instance_types   = var.node_group_instance_types

  tags = {
    Environment = var.environment
    Team        = "DevOps"
  }
}

module "argo-cd" {
  source           = "./modules/argo-cd"
  release_name     = "argocd"
  helm_repo_url    = "https://argoproj.github.io/argo-helm"
  chart_name       = "argo-cd"
  chart_version    = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    server = {
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
        }
      }
    }
  })]
  depends_on = [module.eks_cluster]
}

module "prometheus" {
  source           = "./modules/prometheus"
  release_name     = "prometheus"
  helm_repo_url    = "https://prometheus-community.github.io/helm-charts"
  chart_name       = "kube-prometheus-stack"
  chart_version    = var.prometheus_chart_version
  namespace        = "prometheus"
  create_namespace = true

  values = [yamlencode({
    server = {
      persistentVolume = {
        enabled = true
      }
    }
    grafana = {
      service = {
        type = "LoadBalancer"
      }
    }
    prometheus = {
      service = {
        type = "LoadBalancer"
      }
    }
  })]
  depends_on = [module.argo-cd]
}
