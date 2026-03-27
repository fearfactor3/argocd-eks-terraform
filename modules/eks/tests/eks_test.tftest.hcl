# Native OpenTofu tests for the EKS module.
# All runs use command = plan with mock_provider so no AWS credentials are needed.

mock_provider "aws" {}
mock_provider "tls" {}

# aws_iam_policy_document returns a mock string under mock_provider, which fails
# the IAM JSON validation on aws_iam_role/aws_iam_role_policy/aws_kms_key resources.
# Override all seven documents with minimal valid JSON so the plan can proceed.
# override_data only replaces computed outputs (json); configured arguments
# (statement) are preserved, so the ebs_csi_irsa assertion still tests real values.
override_data {
  target = data.aws_iam_policy_document.eks_cluster_assume_role_policy
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"eks.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.eks_node_assume_role_policy
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.eks_kms_key_policy
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"kms:*\",\"Resource\":\"*\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.node_cloudwatch_logs_read
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"logs:DescribeLogGroups\",\"logs:DescribeLogStreams\",\"logs:GetLogEvents\",\"logs:FilterLogEvents\"],\"Resource\":\"*\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.aws_lb_controller_assume_role
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.aws_lb_controller
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"elasticloadbalancing:*\",\"Resource\":\"*\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.cluster_autoscaler_assume_role
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.cluster_autoscaler
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"autoscaling:DescribeAutoScalingGroups\",\"Resource\":\"*\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.external_secrets_assume_role
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.external_secrets
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":\"*\"}]}"
  }
}

# Mock provider generates non-ARN strings for computed arn attributes.
# aws_eks_cluster validates role_arn, aws_eks_node_group validates node_role_arn,
# aws_eks_addon validates service_account_role_arn, and IAM policy documents
# reference the OIDC provider ARN. Override all IAM roles, the KMS key, and the
# OIDC provider so the plan can proceed without real AWS credentials.
override_resource {
  target = aws_iam_role.eks_cluster_role
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-eks-cluster"
  }
}

override_resource {
  target = aws_iam_role.eks_node_role
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-eks-node"
  }
}

override_resource {
  target = aws_iam_role.ebs_csi
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-ebs-csi"
  }
}

override_resource {
  target = aws_iam_role.aws_lb_controller
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-aws-lb-controller"
  }
}

override_resource {
  target = aws_iam_role.cluster_autoscaler
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-cluster-autoscaler"
  }
}

override_resource {
  target = aws_iam_role.external_secrets
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-external-secrets"
  }
}

override_resource {
  target = aws_kms_key.this
  values = {
    arn = "arn:aws:kms:us-east-1:123456789012:key/mrk-1234567890abcdef"
  }
}

override_resource {
  target = aws_iam_openid_connect_provider.this
  values = {
    arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  }
}

# aws_eks_node_group validates that launch_template.id begins with 'lt-'.
override_resource {
  target = aws_launch_template.nodes
  values = {
    id = "lt-0123456789abcdef0"
  }
}

# Mock provider does not populate computed nested blocks (identity, certificate_authority).
# Override the cluster with realistic values so downstream data sources and outputs
# that index into these blocks (identity[0].oidc[0].issuer, certificate_authority[0].data)
# can resolve during plan.
override_resource {
  target = aws_eks_cluster.this
  values = {
    identity = [{
      oidc = [{
        issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
      }]
    }]
    certificate_authority = [{
      data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBMFZ3PT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
    }]
  }
}

variables {
  cluster_name        = "test-cluster"
  vpc_id              = "vpc-12345678"
  vpc_cidr_block      = "10.0.0.0/16"
  subnet_ids          = ["subnet-aaa", "subnet-bbb"]
  public_access_cidrs = ["1.2.3.4/32"]
}

run "kms_key_rotation_is_enabled" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled for annual automatic rotation."
  }
}

run "all_control_plane_log_types_enabled" {
  command = plan

  assert {
    condition = toset(aws_eks_cluster.this.enabled_cluster_log_types) == toset([
      "api", "audit", "authenticator", "controllerManager", "scheduler"
    ])
    error_message = "All five control plane log types must be shipped to CloudWatch."
  }
}

run "secrets_encrypted_with_kms" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"])
    error_message = "Kubernetes Secrets must be encrypted at rest."
  }
}

run "both_api_endpoint_modes_enabled" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true
    error_message = "Private endpoint access must be enabled."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true
    error_message = "Public endpoint access must be enabled."
  }
}

run "node_group_sizes_within_valid_range" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].min_size >= 1
    error_message = "min_size must be at least 1."
  }

  assert {
    condition = (
      aws_eks_node_group.this.scaling_config[0].desired_size >=
      aws_eks_node_group.this.scaling_config[0].min_size
    )
    error_message = "desired_size must be >= min_size."
  }

  assert {
    condition = (
      aws_eks_node_group.this.scaling_config[0].max_size >=
      aws_eks_node_group.this.scaling_config[0].desired_size
    )
    error_message = "max_size must be >= desired_size."
  }
}

run "imdsv2_enforced_on_node_launch_template" {
  command = plan

  assert {
    condition     = aws_launch_template.nodes.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be enforced (http_tokens = required) on the node launch template."
  }

  assert {
    condition     = aws_launch_template.nodes.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDS hop limit must be 1 to prevent containers from reaching the metadata service."
  }
}

run "ebs_csi_irsa_scoped_to_correct_service_account" {
  command = plan

  assert {
    # statement is a list (indexable); condition is a set (must iterate with for).
    condition = anytrue([
      for cond in data.aws_iam_policy_document.ebs_csi_assume_role.statement[0].condition :
      contains(tolist(cond.values), "system:serviceaccount:kube-system:ebs-csi-controller-sa")
    ])
    error_message = "EBS CSI IRSA trust policy must be scoped to ebs-csi-controller-sa in kube-system."
  }
}
