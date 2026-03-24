# Native OpenTofu tests for the EKS module.
# All runs use command = plan with mock_provider so no AWS credentials are needed.

mock_provider "aws" {}
mock_provider "tls" {}

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
    condition = contains(
      data.aws_iam_policy_document.ebs_csi_assume_role.statement[0].condition[0].values,
      "system:serviceaccount:kube-system:ebs-csi-controller-sa"
    )
    error_message = "EBS CSI IRSA trust policy must be scoped to ebs-csi-controller-sa in kube-system."
  }
}
