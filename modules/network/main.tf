locals {
  # Map of CIDR → AZ, preserving the input pairing by index position.
  # Using CIDR as the for_each key means removing a subnet from the list
  # does not shift the addresses of remaining subnets.
  public_subnets  = { for i, cidr in var.public_subnets : cidr => element(var.azs, i) }
  private_subnets = { for i, cidr in var.private_subnets : cidr => element(var.azs, i) }

  # Base tags merged with caller-provided tags. Resource-specific tags (Name,
  # kubernetes.io/*) are set inline and take precedence over var.tags.
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "opentofu"
    Project     = var.project_name
  })
}

# DNS hostnames and DNS support are both required for EKS nodes to resolve the
# cluster API endpoint and for the VPC-CNI plugin to assign pod IP addresses.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
    # Required by the AWS cloud-controller-manager and ALB/NLB controllers to
    # discover which VPC belongs to this cluster.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# Public subnets host the NAT Gateway and internet-facing load balancers.
# map_public_ip_on_launch is intentionally enabled — required for the NAT EIP
# and for AWS LB controller to provision internet-facing NLBs (see .trivyignore).
# The kubernetes.io/role/elb tag tells the AWS cloud-controller-manager that
# external LoadBalancer services should place their ELBs/NLBs in these subnets.
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.key
  availability_zone       = each.value
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                        = "${var.project_name}-${var.environment}-public-${each.value}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  })
}

# EKS nodes run exclusively in private subnets — they have no public IPs and
# reach the internet only through the NAT Gateway. The internal-elb tag tells
# the AWS cloud-controller-manager to place internal LoadBalancer services here.
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.key
  availability_zone = each.value

  tags = merge(local.common_tags, {
    Name                                        = "${var.project_name}-${var.environment}-private-${each.value}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  })
}

# Single NAT Gateway in the first public subnet. This is a deliberate cost
# trade-off for a test environment — a production setup would deploy one NAT
# Gateway per AZ to eliminate cross-AZ traffic costs and improve resilience.
# depends_on ensures the IGW is attached before the NAT Gateway is created.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-gw"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt"
  })
}

resource "aws_route" "private_nat_access" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# VPC flow logs capture traffic and ship to CloudWatch.
# flow_logs_traffic_type controls what is captured:
#   ALL    — accepted + rejected (prod: full visibility)
#   REJECT — rejected only (~60-80% less volume, reduces CloudWatch ingestion cost in dev)
# Grafana Alloy reads from this log group and forwards records to Loki.
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name = "/aws/vpc-flow-logs/${var.cluster_name}"
  # 7-day retention — appropriate for a test instance. Increase for compliance
  # or long-term trend analysis.
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc-flow-logs"
  })
}

# The VPC flow logs service assumes this role to write log events. The trust
# policy is scoped to the vpc-flow-logs.amazonaws.com principal only — no
# human or other service can assume it.
data "aws_iam_policy_document" "vpc_flow_logs_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${var.cluster_name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_logs_assume.json
  tags               = local.common_tags
}

# Minimum permissions for the flow logs service to write to the log group.
# Resources are scoped to the specific log group ARN — wildcard is not used.
# CreateLogGroup is intentionally omitted because the group is managed by Terraform.
data "aws_iam_policy_document" "vpc_flow_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.vpc_flow_logs.arn,
      "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name   = "vpc-flow-logs-to-cloudwatch"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.vpc_flow_logs.json
}

resource "aws_flow_log" "vpc" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = var.flow_logs_traffic_type
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = local.common_tags
}

# Locking down the default security group prevents accidental assignment to
# resources. AWS creates it automatically and it cannot be deleted, so we
# manage it here to remove all inbound and outbound rules.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-default-sg-do-not-use"
  })
}
