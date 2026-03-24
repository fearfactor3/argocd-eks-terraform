# ADR-004: IRSA for EBS CSI, Node Role for Alloy

**Status**: Accepted

---

## Context

Pods running on EKS nodes need AWS credentials to call AWS APIs. There are two ways to provide them:

| Method | How it works | Scope |
|---|---|---|
| **Node IAM role** | All pods on a node inherit credentials from the EC2 instance profile via the metadata service (IMDSv2). | Any pod on the node can call AWS APIs with the node role's permissions. |
| **IRSA** (IAM Roles for Service Accounts) | A Kubernetes service account is annotated with an IAM role ARN. The pod exchanges its Kubernetes JWT token for temporary AWS credentials scoped to that role. | Only pods using that specific service account in that specific namespace can assume the role. |

Two pods in this cluster need AWS access:

- **EBS CSI controller** — needs `AmazonEBSCSIDriverPolicy` to provision and attach EBS volumes
- **Grafana Alloy** — needs `logs:DescribeLogGroups`, `logs:DescribeLogStreams`, `logs:GetLogEvents`, `logs:FilterLogEvents` to read VPC flow logs from CloudWatch

---

## Decision

- Use **IRSA** for the EBS CSI driver.
- Use the **node IAM role** for Grafana Alloy.

---

## Reasons

### EBS CSI uses IRSA

The EBS CSI driver runs as a privileged controller in `kube-system` and needs broad EBS permissions including `ec2:CreateVolume`, `ec2:AttachVolume`, and `ec2:DeleteVolume`. Putting these permissions on the node role would mean every pod on every node could call these APIs — a significant blast radius if any pod were compromised.

IRSA scopes the permissions to a single service account (`ebs-csi-controller-sa` in `kube-system`) via an IAM condition:

```
StringEquals:
  <oidc-issuer>:sub: system:serviceaccount:kube-system:ebs-csi-controller-sa
```

A compromised pod using a different service account — or any pod in any other namespace — cannot assume this role even on the same node.

### Alloy uses the node role

The CloudWatch Logs read permissions required by Alloy (`logs:Describe*`, `logs:Get*`, `logs:Filter*`) are read-only and carry low blast radius risk. Putting them on the node role is an accepted trade-off for this test environment because:

1. **Simplicity**: IRSA requires the OIDC provider ARN and a matching IAM trust policy with the correct service account condition. For a learning environment, the simpler path reduces noise.
2. **Read-only permissions**: Unlike the EBS CSI driver, Alloy cannot create, modify, or delete any resources with these permissions.
3. **Logs are not sensitive secrets**: CloudWatch Logs data is operational data. Read access to it has a much lower security impact than write access to EBS volumes.

---

## When to upgrade Alloy to IRSA

Move Alloy to IRSA if:

- **Multi-tenant clusters** where different teams' pods share the same nodes and you want to prevent one team's pod from reading another team's CloudWatch logs.
- **Compliance requirements** mandate that all AWS credentials are pod-scoped rather than node-scoped.
- **The node role grows** and restricting it becomes important for least-privilege enforcement.

### How to implement Alloy IRSA

1. Add an IRSA trust policy and IAM role in `modules/eks/main.tf` (or a new `stacks/prometheus` resource), scoped to `system:serviceaccount:prometheus:alloy`.
2. Annotate the Alloy service account via the Helm values:

   ```hcl
   serviceAccount = {
     annotations = {
       "eks.amazonaws.com/role-arn" = aws_iam_role.alloy.arn
     }
   }
   ```

3. Remove the `node_cloudwatch_logs_read` inline policy from the node role in `modules/eks/main.tf`.
