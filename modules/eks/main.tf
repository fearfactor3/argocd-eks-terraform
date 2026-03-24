data "aws_caller_identity" "current" {}

locals {
  policies = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]

  # Use the provided VPC CIDR directly if available; otherwise fall back to the
  # data source lookup. Providing vpc_cidr_block avoids an extra AWS API call
  # during plan and makes the module's inputs explicit.
  vpc_cidr_block = coalesce(var.vpc_cidr_block, try(data.aws_vpc.this[0].cidr_block, null))
}

# Customer-managed KMS key for encrypting Kubernetes Secrets at rest (CKV_AWS_58).
# Key rotation is enabled — AWS automatically rotates the backing key material
# annually while keeping the key ID and alias stable.
resource "aws_kms_key" "this" {
  description             = "KMS key for ${var.cluster_name} EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.this.key_id
}

# The key policy grants the root account full management access so the key
# cannot become unmanageable if the EKS cluster role is deleted. This is the
# AWS-recommended pattern (CKV_AWS_109 / CKV_AWS_111 are suppressed in .checkov.yaml).
resource "aws_kms_key_policy" "eks_secrets" {
  key_id = aws_kms_key.this.id
  policy = data.aws_iam_policy_document.eks_kms_key_policy.json
}

data "aws_iam_policy_document" "eks_kms_key_policy" {
  statement {
    sid    = "EnableRootAccountManagement"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEKSSecretsEncryption"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.eks_cluster_role.arn]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

# EKS writes control plane logs to this group automatically when
# enabled_cluster_log_types is set, but it creates the group without a
# retention policy — logs accumulate at $0.03/GB/month indefinitely.
# Managing the group here lets us set retention before the cluster creates it,
# preventing unbounded CloudWatch costs.
resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.control_plane_log_retention_days
  tags              = var.tags
}

# EKS cluster. The public API endpoint is intentionally enabled so kubectl and
# GitHub Actions can reach it from outside the VPC; access is restricted to
# specific CIDRs via public_access_cidrs (see .trivyignore for AVD-AWS-0040).
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.this.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  # All control plane log types shipped to CloudWatch for audit and debugging.
  # This satisfies CKV_AWS_37 and provides visibility into API server activity,
  # authentication events, and controller decisions.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # CKV_AWS_58: encrypt Kubernetes Secrets with the customer-managed key above.
  # Without this, secrets are encrypted with an AWS-managed key that you cannot
  # audit, rotate, or revoke independently.
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.this.arn
    }
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.eks_control_plane]
}

# Launch template for the managed node group. Enforces IMDSv2 (token-required)
# and sets hop_limit=1 so only the node process itself can reach the EC2
# metadata service — containers on the node cannot impersonate the node IAM
# role by querying IMDS directly. Without this, any container breakout could
# obtain the full node credentials via a single HTTP call to 169.254.169.254.
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only — rejects v1 token-less requests
    http_put_response_hop_limit = 1          # blocks container-level IMDS access
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Managed node group. Nodes run in private subnets (passed in via subnet_ids)
# and are never directly reachable from the internet. All internet egress goes
# through the NAT Gateway in the network stack.
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = var.node_group_desired_capacity
    max_size     = var.node_group_max_capacity
    min_size     = var.node_group_min_capacity
  }

  instance_types = var.node_group_instance_types
  # SPOT reduces EC2 costs by ~60-70% for dev. AWS interrupts spot nodes with a
  # 2-minute warning — acceptable for stateless workloads and dev clusters.
  # Set to ON_DEMAND for prod to avoid workload disruption during reconciliation.
  capacity_type = var.node_capacity_type

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  tags = var.tags
}

# IAM role for the EKS control plane. The trust policy allows only the EKS
# service principal to assume it — no human or other service can.
resource "aws_iam_role" "eks_cluster_role" {
  name               = "${var.cluster_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role_policy.json
}

data "aws_iam_policy_document" "eks_cluster_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Look up the VPC CIDR when not provided directly — used to scope the cluster
# security group ingress rule to traffic originating inside the VPC.
data "aws_vpc" "this" {
  count = var.vpc_cidr_block == null ? 1 : 0
  id    = var.vpc_id
}

# Additional security group attached to the EKS control plane. Restricts HTTPS
# (port 443) ingress to the VPC CIDR so the API server is only reachable from
# inside the network (or via the public endpoint CIDRs configured above).
# Egress is unrestricted — nodes need to reach ECR, S3, and AWS service APIs
# (see .trivyignore for AVD-AWS-0104).
resource "aws_security_group" "this" {
  name        = "${var.cluster_name}-eks-cluster-sg"
  description = "EKS cluster API server — restricts HTTPS ingress to VPC CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    description = "Allow all egress for node-to-AWS-API communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# IAM role attached to EC2 nodes via an instance profile. The three managed
# policies below are the minimum required for nodes to join the cluster, pull
# images from ECR, and configure pod networking via the VPC-CNI plugin.
resource "aws_iam_role" "eks_node_role" {
  name               = "${var.cluster_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role_policy.json
}

data "aws_iam_policy_document" "eks_node_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "eks_role_attachment" {
  for_each   = toset(local.policies)
  role       = aws_iam_role.eks_node_role.name
  policy_arn = each.value
}

# Allow nodes to read CloudWatch Logs so Grafana Alloy can ship VPC flow logs
# to Loki. Alloy runs as a pod on these nodes and inherits credentials from the
# EC2 instance metadata service (IMDSv2) — no secrets are stored in the cluster.
# Pass var.cloudwatch_log_group_arns to scope to specific log groups (least-privilege);
# defaults to ["*"] for backwards compatibility when the ARN is not known at plan time.
data "aws_iam_policy_document" "node_cloudwatch_logs_read" {
  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
    ]
    resources = var.cloudwatch_log_group_arns
  }
}

resource "aws_iam_role_policy" "node_cloudwatch_logs_read" {
  name   = "cloudwatch-logs-read-for-alloy"
  role   = aws_iam_role.eks_node_role.id
  policy = data.aws_iam_policy_document.node_cloudwatch_logs_read.json
}

# OIDC provider for IRSA (IAM Roles for Service Accounts). This allows
# individual Kubernetes service accounts to assume scoped IAM roles via a JWT
# token rather than sharing the broad node instance profile. The EBS CSI driver
# below is the first consumer; any future service needing AWS access should use
# the same pattern instead of expanding the node role.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# IRSA role for the EBS CSI driver. The condition restricts assumption to the
# specific service account (ebs-csi-controller-sa in kube-system) — any other
# pod on the same node cannot assume this role even though the node's OIDC
# provider is the same.
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Managed add-ons are AWS-maintained versions of core cluster components.
# Versions are pinned and tracked by Renovate — bump deliberately after reading
# the add-on changelog, as some versions require node drains or API migrations.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = var.vpc_cni_addon_version
  tags          = var.tags
}

# coredns requires nodes to be ready before it can schedule, hence the
# dependency on the node group.
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = var.coredns_addon_version
  tags          = var.tags

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = var.kube_proxy_addon_version
  tags          = var.tags
}

# The EBS CSI driver is deployed as a managed add-on and uses the IRSA role
# created above. service_account_role_arn wires the annotation that the driver's
# service account needs to exchange its JWT for AWS credentials.
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_addon_version
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  tags                     = var.tags

  depends_on = [aws_eks_node_group.this, aws_iam_role_policy_attachment.ebs_csi]
}

# Scheduled scale-down for dev clusters. When enable_scheduled_scaling = true,
# the node group ASG is scaled to 0 each weekday evening and restored each
# morning. This reduces EC2 costs by ~70% for clusters not needed overnight.
#
# The ASG name is obtained from the managed node group's resources attribute —
# EKS manages the ASG lifecycle, but we can still attach schedule actions to it.
#
# Weekends are not covered: scale-down fires Friday evening and scale-up fires
# Monday morning, keeping the cluster off all weekend automatically.
# IRSA role for the AWS Load Balancer Controller. The LB controller watches
# Ingress and Service resources and provisions ALBs/NLBs on behalf of the cluster.
# Scoped to the specific service account in kube-system — same pattern as the
# EBS CSI driver above.
data "aws_iam_policy_document" "aws_lb_controller_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${var.cluster_name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume_role.json
  tags               = var.tags
}

# The AWSLoadBalancerControllerIAMPolicy document is published by AWS and
# grants the minimum permissions needed to manage ALBs, NLBs, target groups,
# security groups, and the related EC2/ELB APIs.
data "aws_iam_policy_document" "aws_lb_controller" {
  statement {
    sid    = "AllowELBManagement"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCognitoAndACM"
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEC2Mutations"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DeleteSecurityGroup",
      "ec2:ModifyNetworkInterfaceAttribute",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowELBMutations"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "aws_lb_controller" {
  name   = "aws-lb-controller-policy"
  role   = aws_iam_role.aws_lb_controller.id
  policy = data.aws_iam_policy_document.aws_lb_controller.json
}

resource "aws_autoscaling_schedule" "scale_down" {
  count = var.enable_scheduled_scaling ? 1 : 0

  scheduled_action_name  = "${var.cluster_name}-scale-down"
  autoscaling_group_name = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name
  recurrence             = var.scale_down_cron
  min_size               = 0
  max_size               = var.node_group_max_capacity
  desired_capacity       = 0
}

resource "aws_autoscaling_schedule" "scale_up" {
  count = var.enable_scheduled_scaling ? 1 : 0

  scheduled_action_name  = "${var.cluster_name}-scale-up"
  autoscaling_group_name = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name
  recurrence             = var.scale_up_cron
  min_size               = var.node_group_min_capacity
  max_size               = var.node_group_max_capacity
  desired_capacity       = var.node_group_desired_capacity
}
