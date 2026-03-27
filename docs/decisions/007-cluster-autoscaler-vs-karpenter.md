# ADR-007: Cluster Autoscaler vs. Karpenter vs. Fixed Node Sizing

**Status**: Accepted — Option A (Cluster Autoscaler)

---

## Context

EKS node groups are currently configured with a fixed `desired_size`. No cluster autoscaler is deployed. Nodes run at the desired count continuously, including overnight and on weekends when workloads are idle.

For the dev environment (desired=2, instance=t3.medium), this costs approximately $60–70/month in EC2 charges regardless of actual utilization.

Two autoscaling solutions are available for EKS:

| Tool | Model |
|------|-------|
| **Cluster Autoscaler (CA)** | Watches for unschedulable pods; scales the existing managed node group up. Scales down nodes that have been underutilized for a configurable period. |
| **Karpenter** | Node provisioner that creates EC2 instances directly (bypassing the managed node group). Selects the most cost-efficient instance type for each workload's requirements. Supports Spot natively. |

---

## Options Considered

### Option A: Cluster Autoscaler

Deploy CA via the `cluster-autoscaler` Helm chart. CA watches `kube-system` events and calls the Auto Scaling Group API to adjust the managed node group's desired count.

**Pros:**

- Mature, well-documented, widely deployed
- Works directly with the existing `aws_eks_node_group` (ASG-backed)
- Simple IRSA setup: one IAM role with `autoscaling:*` and `ec2:Describe*`
- Understood failure modes

**Cons:**

- Slower to scale down (default 10-minute underutilization window before a node is removed)
- Does not select instance types — still bound to the instance types in the node group
- Bin-packing is less efficient than Karpenter

### Option B: Karpenter

Deploy Karpenter and replace the managed node group with `NodePool` and `EC2NodeClass` resources. Karpenter provisions EC2 instances directly from the instance metadata API.

**Pros:**

- Significantly faster scale-up (seconds vs. minutes)
- Selects the cheapest available instance type that satisfies pod requirements
- Native Spot + On-Demand mixed provisioning with automatic fallback
- Consolidation: actively bin-packs and terminates underutilized nodes

**Cons:**

- Replaces the managed node group — requires a node group migration
- More complex initial setup (IRSA, NodePool, EC2NodeClass resources)
- Newer project; more frequent API changes across versions
- `NodePool` and `EC2NodeClass` are cluster-scoped resources, not managed by the existing OpenTofu modules without additional work

### Option C: Fixed Sizing (current)

No autoscaler. Nodes run at `desired_size` continuously.

**Pros:**

- Zero operational complexity
- Predictable costs
- Appropriate for initial bootstrap and early development

**Cons:**

- Full cost even when cluster is idle (nights, weekends)
- Cannot handle traffic spikes automatically

---

## Decision

**Option A — Cluster Autoscaler** is deployed in `stacks/eks-addons` via Helm. The managed node group in `modules/eks` is tagged for CA discovery, and an IRSA role scoped to the `kube-system:cluster-autoscaler` service account grants the minimum required ASG permissions.

Karpenter remains a future option if Spot instance management or sub-minute scale-up becomes a priority. It would require migrating away from the managed node group, which is a larger change best deferred until the cluster is proven stable.

---

## Implementation Notes (Cluster Autoscaler)

When implementing CA:

1. Tag the managed node group ASG:

   ```text
   k8s.io/cluster-autoscaler/enabled = "true"
   k8s.io/cluster-autoscaler/<cluster-name> = "owned"
   ```

   These tags can be added to the `aws_eks_node_group` resource via `tags`.

2. Add an IRSA role in `modules/eks/main.tf` scoped to `system:serviceaccount:kube-system:cluster-autoscaler`.

3. Deploy via Helm in a new `stacks/cluster-addons` stack (or add to `stacks/prometheus` if keeping addons co-located).
