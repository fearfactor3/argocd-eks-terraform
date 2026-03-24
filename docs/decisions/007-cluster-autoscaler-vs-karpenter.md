# ADR-007: Cluster Autoscaler vs. Karpenter vs. Fixed Node Sizing

**Status**: Open — decision pending

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

**Not yet made.** Recommended path:

1. **Short-term**: Keep fixed sizing for the initial bootstrap. Validate the cluster is stable before adding autoscaling complexity.
2. **Medium-term (dev)**: Add Cluster Autoscaler. Scale `min_size=1` to allow the cluster to drop to a single node during idle periods. Expected saving: ~$30–35/month (one t3.medium eliminated overnight/weekends).
3. **Long-term (prod)**: Evaluate Karpenter when Spot instances are introduced for non-critical workloads. Karpenter's Spot fallback logic is more robust than CA's.

---

## Implementation Notes (Cluster Autoscaler)

When implementing CA:

1. Tag the managed node group ASG:
   ```
   k8s.io/cluster-autoscaler/enabled = "true"
   k8s.io/cluster-autoscaler/<cluster-name> = "owned"
   ```
   These tags can be added to the `aws_eks_node_group` resource via `tags`.

2. Add an IRSA role in `modules/eks/main.tf` scoped to `system:serviceaccount:kube-system:cluster-autoscaler`.

3. Deploy via Helm in a new `stacks/cluster-addons` stack (or add to `stacks/prometheus` if keeping addons co-located).
