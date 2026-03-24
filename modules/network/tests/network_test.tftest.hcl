# Native OpenTofu tests for the network module.
# All runs use command = plan with mock_provider so no AWS credentials are needed.

mock_provider "aws" {}

# aws_iam_policy_document returns a mock string under mock_provider, which fails
# the IAM JSON validation on aws_iam_role.assume_role_policy. Override both
# policy documents with minimal valid JSON so the plan can proceed.
override_data {
  target = data.aws_iam_policy_document.vpc_flow_logs_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"vpc-flow-logs.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.vpc_flow_logs
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogStream\",\"logs:PutLogEvents\",\"logs:DescribeLogGroups\",\"logs:DescribeLogStreams\"],\"Resource\":\"*\"}]}"
  }
}

# Mock provider generates non-ARN strings for computed attributes; aws_flow_log
# validates that iam_role_arn and log_destination are valid ARNs. Override both
# upstream resources so the mock values pass format validation.
override_resource {
  target = aws_iam_role.vpc_flow_logs
  values = {
    arn = "arn:aws:iam::123456789012:role/test-cluster-vpc-flow-logs"
  }
}

override_resource {
  target = aws_cloudwatch_log_group.vpc_flow_logs
  values = {
    arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/vpc-flow-logs/test-cluster"
  }
}

variables {
  vpc_cidr        = "10.0.0.0/16"
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  azs             = ["us-east-1a", "us-east-1b"]
  project_name    = "test"
  environment     = "dev"
  cluster_name    = "test-cluster"
}

run "vpc_has_correct_cidr_and_dns" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == var.vpc_cidr
    error_message = "VPC CIDR block does not match the requested value."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames must be enabled for EKS node resolution."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "DNS support must be enabled for EKS node resolution."
  }
}

run "subnet_count_matches_input" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == length(var.public_subnets)
    error_message = "Number of public subnets does not match the input list length."
  }

  assert {
    condition     = length(aws_subnet.private) == length(var.private_subnets)
    error_message = "Number of private subnets does not match the input list length."
  }
}

run "subnets_keyed_by_cidr" {
  command = plan

  assert {
    condition     = contains(keys(aws_subnet.public), "10.0.1.0/24")
    error_message = "Public subnet should be keyed by its CIDR block."
  }

  assert {
    condition     = contains(keys(aws_subnet.private), "10.0.3.0/24")
    error_message = "Private subnet should be keyed by its CIDR block."
  }
}

run "flow_logs_capture_all_traffic" {
  command = plan

  assert {
    condition     = aws_flow_log.vpc.traffic_type == "ALL"
    error_message = "Flow logs must capture ALL traffic (accepted and rejected)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.vpc_flow_logs.retention_in_days == 7
    error_message = "Flow log retention should be 7 days."
  }
}

run "default_sg_has_no_rules" {
  command = plan

  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0
    error_message = "Default security group must have no ingress rules."
  }

  assert {
    condition     = length(aws_default_security_group.default.egress) == 0
    error_message = "Default security group must have no egress rules."
  }
}
