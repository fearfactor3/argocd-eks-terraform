# ADR-005: NLB per Service vs. ALB Ingress Controller

**Status**: Open — decision pending

---

## Context

Two internal tooling services (ArgoCD and Grafana) are each exposed via a dedicated AWS Network Load Balancer, provisioned by setting `service.type: LoadBalancer` in their Helm values. This results in:

- `argo-cd-dev` NLB, `argo-cd-prod` NLB
- `prometheus-dev` NLB, `prometheus-prod` NLB

Four NLBs total across two environments, each with a flat ~$16/month base cost plus LCU charges, regardless of traffic volume.

The alternative is to deploy the **AWS Load Balancer Controller** (formerly AWS ALB Ingress Controller) as a cluster add-on, then expose all internal tooling through a single ALB using host-based or path-based routing via `Ingress` resources.

---

## Options Considered

| Option | Model | Cost | Complexity |
|--------|-------|------|------------|
| **NLB per service** (current) | `service.type: LoadBalancer` on each Helm release | ~$16/service/month | Low — no additional controller |
| **ALB Ingress Controller** | Single ALB, multiple `Ingress` resources with host routing | ~$16–22/cluster/month total | Medium — IRSA role, controller Helm chart, DNS, TLS |
| **kubectl port-forward** (dev only) | No load balancer, access via local port-forward | $0 | Low, but not a production solution |

---

## Decision

**Not yet made.** The following criteria should drive the choice:

1. **If DNS + TLS is implemented**: ALB Ingress Controller is clearly better. A single ALB with ACM certificates terminates HTTPS and routes by hostname (`argocd.example.com`, `grafana.example.com`). NLBs would require separate ACM certificates per service and no L7 routing.

2. **If the cluster stays internal-only**: `kubectl port-forward` for dev and a single NLB for prod-ArgoCD (which needs reliable external gRPC access) is a reasonable compromise.

3. **If cost is the priority**: ALB Ingress Controller consolidates all services behind one load balancer in each environment, cutting 3 of the 4 NLBs.

---

## Trade-offs

**ALB Ingress Controller:**
- Requires an IRSA role scoped to the controller service account (`aws-load-balancer-controller` in `kube-system`)
- Requires DNS entries per service (Route 53 or manual)
- Requires ACM certificates per domain or a wildcard cert
- ArgoCD's gRPC CLI (`argocd login`) works on NLB (L4); on ALB it requires an `alb.ingress.kubernetes.io/backend-protocol-version: GRPC` annotation

**NLB per service (current):**
- Simple — no additional controller, no DNS, no certificate management
- Cost scales linearly with the number of services exposed
- Each NLB is a separate attack surface with no L7 filtering

---

## Recommendation

Implement ALB Ingress Controller when TLS is added (see ADR-005 dependency on cert-manager decision). Until then, the NLB-per-service approach is acceptable for a non-production state. Do not add further NLB-backed services before this decision is resolved.
