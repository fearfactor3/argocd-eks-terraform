provider "kubernetes" {
  host                   = module.eks_cluster.eks_cluster_endpoint
  token                  = data.aws_eks_cluster_auth.auth.token
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.eks_cluster_endpoint
    token                  = data.aws_eks_cluster_auth.auth.token
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_ca_certificate)
  }
}

data "aws_eks_cluster_auth" "auth" {
  name = module.eks_cluster.eks_cluster_name
}
