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
