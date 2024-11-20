module "network" {
  source         = "./modules/network"
  vpc_cidr       = "x.x.x.x" # CHANGE THIS
  public_subnets = ["x.x.x.x"] # CHANGE THIS
  azs            = ["us-east-1a", "us-east-1b"] # CHANGE THIS
  project_name   = "argocd" 
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