# The AWS Load Balancer Controller replaces the legacy cloud-controller-manager
# for ELB/ALB provisioning. It watches Ingress resources and provisions a single
# ALB per Ingress, replacing the previous pattern where each Service of type
# LoadBalancer got its own NLB (~$16/month each).
#
# This consolidation reduces two separate NLBs (ArgoCD + Grafana) into one ALB
# per cluster, saving ~$16-32/month per environment.
#
# The controller uses IRSA (IAM Roles for Service Accounts) so only the
# aws-load-balancer-controller service account can assume the role — the node
# instance profile is not broadened.
# Cluster Autoscaler watches for pods that cannot be scheduled due to
# insufficient node capacity. When found, it calls the Auto Scaling API to
# increase the node group's desired count. It also scales down nodes that
# have been underutilised for the configured period (default: 10 minutes).
#
# Uses IRSA so only the cluster-autoscaler service account can assume the role.
# The IAM policy (in modules/eks/main.tf) restricts ASG mutations to node groups
# tagged k8s.io/cluster-autoscaler/enabled=true.
resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = var.cluster_autoscaler_chart_version
  namespace        = "kube-system"
  create_namespace = false

  values = [yamlencode({
    autoDiscovery = {
      clusterName = var.eks_cluster_name
    }
    awsRegion = var.aws_region
    serviceAccount = {
      create = true
      name   = "cluster-autoscaler"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.cluster_autoscaler_role_arn
      }
    }
    extraArgs = {
      "balance-similar-node-groups" = true
      "skip-nodes-with-system-pods" = false
    }
    commonLabels = {
      environment = var.environment
    }
  })]
}

# External Secrets Operator pulls secrets from external stores (AWS Secrets
# Manager, SSM Parameter Store) and materialises them as Kubernetes Secret
# objects. Application teams create ExternalSecret CRs in their namespaces
# referencing secrets by path — no secret values are stored in Git.
#
# The ESO service account uses IRSA to assume the external-secrets IAM role,
# which is scoped to secrets under the /<cluster-name>/ path prefix.
# See docs/runbooks/configure-external-secrets.md for ClusterSecretStore setup.
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  values = [yamlencode({
    serviceAccount = {
      create = true
      name   = "external-secrets"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.external_secrets_role_arn
      }
    }
    commonLabels = {
      environment = var.environment
    }
  })]
}

# The AWS Load Balancer Controller replaces the legacy cloud-controller-manager
resource "helm_release" "aws_lb_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = var.aws_lb_controller_chart_version
  namespace        = "kube-system"
  create_namespace = false

  values = [yamlencode({
    clusterName = var.eks_cluster_name
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        # Wire IRSA — the controller exchanges its Kubernetes service account
        # JWT for temporary AWS credentials scoped to this role.
        "eks.amazonaws.com/role-arn" = var.aws_lb_controller_role_arn
      }
    }
    # Single replica is sufficient for dev; increase for prod HA.
    replicaCount = 1
    commonLabels = {
      environment = var.environment
    }
  })]
}
