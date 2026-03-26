# ADR-009: TLS Termination and Certificate Management

**Status**: Accepted — Option A (ALB + ACM). `certificate_arn` variable wired into `argo-cd` and `prometheus` stacks. TLS activates when a cert ARN is provided; HTTP-only when empty (default for homelab). Pending: Route 53 hosted zone and ACM certificate provisioning once a domain is registered.

---

## Context

ArgoCD and Grafana are currently exposed over plaintext HTTP via ALB Ingress (see [ADR-005](005-nlb-per-service-vs-alb-ingress.md)). Credentials (ArgoCD login, Grafana login) cross the network unencrypted. This is acceptable during initial bootstrap but must be resolved before production use.

TLS for Kubernetes services can be handled at several layers:

| Layer | Approach |
| ----- | -------- |
| **Ingress (L7)** | ALB Ingress Controller terminates TLS with an ACM certificate. Workloads see plaintext internally. |
| **NLB with ACM (L4)** | NLB passes TLS to the pod; ACM certificate is attached to the NLB listener. Requires TLS passthrough to the pod or NLB termination. |
| **cert-manager (in-cluster)** | cert-manager issues certificates (Let's Encrypt or ACM via Route 53) and stores them as Kubernetes `Secret` objects. Works with any ingress controller. |

---

## Options Considered

### Option A: ALB Ingress Controller + ACM Certificates

Deploy the AWS Load Balancer Controller (see ADR-005). Expose ArgoCD and Grafana via `Ingress` resources with ACM certificate ARN annotations. TLS terminates at the ALB.

**Pros:**

- ACM certificates are free and auto-renew
- Single ALB serves all services (resolves ADR-005 NLB cost problem simultaneously)
- No in-cluster certificate management required
- ArgoCD gRPC works on ALB with `backend-protocol-version: GRPC` annotation

**Cons:**

- Requires DNS — each service needs a hostname record pointing to the ALB
- Requires ALB Ingress Controller (IRSA role + Helm chart)
- Initial setup is more involved than current NLB approach

### Option B: cert-manager + Let's Encrypt

Deploy cert-manager with a `ClusterIssuer` using Let's Encrypt DNS-01 challenge (Route 53). cert-manager issues certificates and stores them as `Secret` objects in each namespace.

**Pros:**

- Works with any ingress controller or NLB
- Fully automated certificate lifecycle
- No ACM dependency

**Cons:**

- cert-manager must be deployed and managed as a cluster add-on
- Let's Encrypt certificates require DNS-01 or HTTP-01 challenge — DNS-01 requires Route 53 access (IRSA)
- Certificate `Secret` objects are in-cluster — still need KMS encryption at rest (already configured)

### Option C: Keep HTTP (current)

No change. Continue to use HTTP for internal tooling.

**Pros:**

- Zero additional complexity

**Cons:**

- Credentials transmitted in plaintext
- Not acceptable for production

---

## Decision

**Not yet made.** Recommended path:

**Option A (ALB + ACM)** is the recommended approach for production because it:

- Solves TLS and the duplicate NLB cost problem (ADR-005) in a single change
- Uses ACM which has no certificate management overhead (auto-renewal, no ACME challenges)
- Keeps certificate complexity outside the cluster

**Prerequisite:** Route 53 hosted zone and DNS for the cluster's domain must be established before ALB hostnames can be created.

---

## Action Required

Before production go-live:

1. Establish a Route 53 hosted zone for the cluster domain
2. Provision ACM certificate(s) via `aws_acm_certificate` in the appropriate stack
3. Add `alb.ingress.kubernetes.io/certificate-arn` annotation to the existing `Ingress` resources in `stacks/argo-cd/main.tf` and `stacks/prometheus/main.tf`
4. Update this ADR to `Accepted`

> **Note:** Steps previously required to deploy the ALB Ingress Controller and replace `service.type: LoadBalancer` with `Ingress` resources are complete — resolved by [ADR-005](005-nlb-per-service-vs-alb-ingress.md).
