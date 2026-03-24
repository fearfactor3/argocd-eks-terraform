# ADR-005: NLB per Service vs. ALB Ingress Controller

**Status**: Accepted — ALB Ingress Controller implemented

---

## Context

Two internal tooling services (ArgoCD and Grafana) were initially considered for exposure via dedicated AWS Network Load Balancers, each with a flat ~$16/month base cost plus LCU charges, regardless of traffic volume.

The **AWS Load Balancer Controller** (formerly AWS ALB Ingress Controller) was chosen as the alternative — deployed as a cluster add-on in `stacks/eks-addons`, exposing all internal tooling through a single ALB using host-based routing via `Ingress` resources.

---

## Options Considered

| Option | Model | Cost | Complexity |
|--------|-------|------|------------|
| **NLB per service** (current) | `service.type: LoadBalancer` on each Helm release | ~$16/service/month | Low — no additional controller |
| **ALB Ingress Controller** | Single ALB, multiple `Ingress` resources with host routing | ~$16–22/cluster/month total | Medium — IRSA role, controller Helm chart, DNS, TLS |
| **kubectl port-forward** (dev only) | No load balancer, access via local port-forward | $0 | Low, but not a production solution |

---

## Decision

**ALB Ingress Controller** — implemented in `stacks/eks-addons`. ArgoCD and Grafana both use `service.type: ClusterIP` with `Ingress` resources annotated for the ALB. The controller runs as a single-replica Deployment with an IRSA role scoped to `aws-load-balancer-controller` in `kube-system`.

Cost savings driven this: a single ALB per environment replaces what would have been four NLBs (~$64/month total) at roughly the same ALB base cost (~$16–22/cluster/month).

TLS is still pending (see [ADR-009](009-tls-and-ingress.md)) — services currently serve HTTP. The ALB Ingress is in place and ready for ACM certificates once a Route 53 hosted zone is established.

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

## Next Steps

TLS termination via ACM (see [ADR-009](009-tls-and-ingress.md)) is the remaining open item. The ALB Ingress annotations for `ssl-redirect` and `listen-ports` are already in place in both `stacks/argo-cd/main.tf` and `stacks/prometheus/main.tf` — only an ACM certificate ARN annotation and a Route 53 record are needed to complete the TLS configuration.
