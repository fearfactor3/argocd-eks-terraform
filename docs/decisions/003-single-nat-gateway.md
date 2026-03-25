# ADR-003: Single NAT Gateway per Environment

**Status**: Accepted

---

## Context

EKS nodes run in private subnets and need outbound internet access to reach ECR, S3, and AWS service APIs. A NAT Gateway in a public subnet provides this. The question is how many NAT Gateways to deploy per environment.

Two options were considered:

| Option | NAT Gateways | Cost (approx.) | Resilience |
|---|---|---|---|
| **Single NAT Gateway** | 1, in the first public subnet (AZ-a) | ~$32/month + data transfer | AZ-a failure = all private subnet internet egress fails |
| **One per AZ** | 1 per availability zone (2 in this setup) | ~$64/month + data transfer | AZ failure = only that AZ loses egress; other AZs unaffected |

---

## Decision

Deploy a **single NAT Gateway** in the first public subnet.

---

## Reasons

### This is a test / learning environment

The primary purpose of this project is to learn and experiment. The additional resilience of per-AZ NAT Gateways is not worth the doubled cost for a non-production workload. When the environment is not running, the cost is effectively zero — a NAT Gateway that is rarely under load costs mostly the fixed hourly rate regardless of how many you deploy.

### Cross-AZ data transfer cost avoidance is less relevant here

The other reason teams use per-AZ NAT Gateways is to avoid cross-AZ data transfer charges: if a node in AZ-b routes egress traffic through a NAT Gateway in AZ-a, AWS charges for the cross-AZ traffic. At low data volumes (typical for a test environment), this cost is negligible.

---

## When to revisit

Move to one NAT Gateway per AZ when:

- **This becomes a production environment** where AZ-level resilience is required
- **Data transfer costs become significant** due to high egress volume from nodes in non-primary AZs
- **SLA requirements** cannot tolerate the scenario where a single AZ failure takes down all node egress

---

## Implementation

To migrate to per-AZ NAT Gateways, replace the single `aws_nat_gateway` and `aws_eip` in `modules/network/main.tf` with `count`-based resources (one per AZ), and create a separate private route table per AZ each pointing at its local NAT Gateway:

```hcl
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_nat_access" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}
```

Then associate each private subnet with the route table for its AZ rather than a shared table.
