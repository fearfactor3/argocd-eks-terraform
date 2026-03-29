# Architecture

## Overview

This project provisions two fully isolated EKS environments (dev and prod) on AWS, each with its own VPC, EKS cluster, and observability stack. All infrastructure is managed as independent OpenTofu stacks orchestrated by Spacelift.

The design follows three principles:

- **Isolation** — dev and prod share no AWS resources. A misconfiguration or destructive change in dev cannot affect prod.
- **GitOps** — Argo CD is the only mechanism that deploys application workloads into the cluster. Direct `kubectl apply` is discouraged.
- **Policy as code** — Spacelift plan and approval policies enforce guardrails in CI before any `tofu apply` runs in production.

---

## Stack Dependency Graph

```text
iam  (shared, deployed once per AWS account)

network-dev ──► eks-dev ──► eks-addons-dev ──► kyverno-dev ──► argo-cd-dev
                                                            └─► prometheus-dev

network-prod ──► eks-prod ──► eks-addons-prod ──► kyverno-prod ──► argo-cd-prod
                                                              └─► prometheus-prod

spacelift  (meta-stack — manages all stacks above as code)
```

Arrows indicate a Spacelift stack dependency: the downstream stack waits for the upstream stack to finish applying before it runs. Cross-stack outputs (VPC ID, subnet IDs, cluster endpoint, CA certificate) are automatically injected as `TF_VAR_*` environment variables into the dependent stack by Spacelift.

---

## Components

### IAM stack

Deployed once per AWS account, outside the per-environment loop.

- Creates a GitHub Actions OIDC provider so CI jobs can assume an IAM role without storing long-lived credentials.
- The plan role is read-only (Describe/List/Get) and scoped to `pull_request` events only — it cannot apply or destroy anything.

### Network stack (per environment)

Provisions the foundational layer that every other stack depends on.

| Resource | Purpose |
| --- | --- |
| VPC | Isolated network boundary. DNS hostnames and DNS support are enabled — required for EKS node discovery and VPC-CNI. |
| Public subnets | Host NAT Gateway EIPs and internet-facing ALB. Tagged `kubernetes.io/role/elb` for ALB controller discovery. |
| Private subnets | Host EKS nodes. No public IPs. Tagged `kubernetes.io/role/internal-elb`. |
| Internet Gateway | Provides public subnets with a route to the internet. |
| NAT Gateway | Provides private subnets with outbound internet access (single instance — see [ADR-003](decisions/003-single-nat-gateway.md)). |
| VPC Flow Logs | Captures all accepted and rejected traffic and ships it to CloudWatch Logs. See [Observability Pipeline](#observability-pipeline) below. |
| Default SG | Managed by Terraform with no rules — prevents accidental assignment to resources. |

### EKS stack (per environment)

| Resource | Purpose |
| --- | --- |
| EKS cluster | Control plane with all log types enabled (api, audit, authenticator, controllerManager, scheduler). |
| KMS key | Customer-managed key for encrypting Kubernetes Secrets at rest. Key rotation is enabled. |
| Node group | Managed node group running in private subnets. Sizing is controlled per-environment via the `environments` variable in the Spacelift stack. |
| Node IAM role | Instance profile for EC2 nodes. Carries minimum required policies plus a CloudWatch Logs read policy for Alloy (see [Observability Pipeline](#observability-pipeline)). |
| OIDC provider | Enables IRSA — service accounts can assume scoped IAM roles via JWT exchange rather than relying on the broad node role. |
| EBS CSI driver | Managed add-on with a dedicated IRSA role scoped to the `ebs-csi-controller-sa` service account in `kube-system`. See [ADR-004](decisions/004-irsa-over-node-role.md). |
| Security group | Attached to the control plane. Restricts HTTPS (443) ingress to the VPC CIDR only. |

### EKS Addons stack (per environment)

Deploys cluster-level add-ons that must be running before application stacks can create `Ingress` resources.

| Release | Purpose |
| --- | --- |
| `aws-load-balancer-controller` | Watches `Ingress` resources and provisions ALBs on AWS. Runs with an IRSA role scoped to `aws-load-balancer-controller` in `kube-system`. |

This stack also re-exports the EKS cluster credentials (`eks_cluster_name`, `eks_cluster_endpoint`, `cluster_ca_certificate`) as outputs so downstream stacks receive them via the `eks-addons` dependency rather than directly from `eks`.

### Kyverno stack (per environment)

Deploys the Kyverno admission controller and `kyverno-policies` Helm releases into the `kyverno` namespace (PSS `restricted` enforced).

Kyverno sits between `eks-addons` and `{argo-cd, prometheus}` so the admission webhook is guaranteed live before any application pods are scheduled.

| Release | Chart | Purpose |
| --- | --- | --- |
| `kyverno` | kyverno/kyverno | Admission controller, background controller, cleanup controller, reports controller. dev=1 replica, prod=3 replicas. |
| `kyverno-policies` | kyverno/kyverno-policies | `podSecurity` and `bestPractices` ClusterPolicy groups. All policies run in `Audit` mode — violations reported, nothing blocked. |

**Policy groups enabled:**

- `podSecurity` — mirrors PSS restricted profile: disallow-host-namespaces, disallow-privileged-containers, restrict-seccomp, require-run-as-nonroot, etc.
- `bestPractices` — disallow-latest-tag, require-pod-requests-limits, require-labels

**Known expected violations**: node-exporter in the `prometheus` namespace requires privileged capabilities and will generate Audit violations. These are non-blocking. A `PolicyException` should be created before promoting those policies to Enforce.

This stack also re-exports cluster credentials as pass-through outputs so `argo-cd` and `prometheus` receive them through the kyverno dependency.

### Argo CD stack (per environment)

Deploys Argo CD via Helm into the `argocd` namespace. Exposed externally via ALB Ingress at `argocd.<environment>.internal`.

Argo CD is the GitOps engine — it watches a Git repository and continuously reconciles the cluster state to match what is declared there. Application deployments should go through Argo CD rather than direct `kubectl apply`.

### Prometheus stack (per environment)

Deploys three Helm releases into the `prometheus` namespace:

| Release | Chart | Purpose |
| --- | --- | --- |
| `prometheus` | kube-prometheus-stack | Prometheus, Alertmanager, and Grafana. Grafana is exposed via ALB Ingress at `grafana.<environment>.internal`. |
| `loki` | grafana/loki | Log aggregation backend in SingleBinary mode. |
| `alloy` | grafana/alloy | Collects VPC flow logs from CloudWatch and ships them to Loki. |

### Spacelift stack (meta-stack)

The Spacelift stack is itself an OpenTofu stack that creates and manages all other stacks as code. This is sometimes called a "meta-stack" pattern.

It uses `setproduct(environments, stack_types)` to generate the full matrix of per-environment stacks without repetition, then:

1. Creates each `spacelift_stack` resource
2. Injects per-environment configuration as `TF_VAR_*` environment variables
3. Wires `spacelift_stack_dependency` and `spacelift_stack_dependency_reference` resources to pass cross-stack outputs automatically

When you change an environment's node sizing in `variables.tf` and apply the Spacelift stack, Spacelift updates the downstream stacks on the next run.

---

## Observability Pipeline

VPC flow logs cannot be shipped directly to Loki — AWS only supports CloudWatch Logs, S3, or Kinesis Firehose as flow log destinations. The pipeline bridges this gap:

```text
VPC (all traffic)
  │
  │  aws_flow_log (modules/network/main.tf)
  ▼
CloudWatch Logs
  /aws/vpc-flow-logs/<cluster-name>
  │
  │  otelcol.receiver.awscloudwatch  (Grafana Alloy)
  │  → otelcol.exporter.loki → loki.write
  │  polls every 60 seconds
  ▼
Loki  (http://loki:3100)
  │
  │  Loki datasource
  ▼
Grafana  (ALB Ingress)
```

**Credentials**: Alloy runs on EKS nodes and inherits AWS credentials from the EC2 instance metadata service (IMDSv2). The node IAM role has `logs:DescribeLogGroups`, `logs:DescribeLogStreams`, `logs:GetLogEvents`, and `logs:FilterLogEvents` permissions. No Kubernetes secrets or IRSA are needed.

**Log group naming**: `modules/network/main.tf` creates the log group at `/aws/vpc-flow-logs/<cluster_name>`. The Alloy River config in `stacks/prometheus/main.tf` derives the same name from `var.eks_cluster_name`, which is the same value injected by Spacelift — no manual coordination is required.

---

## Security Model

### Identity and access

```text
GitHub Actions (pull_request)
  │  OIDC token → sts:AssumeRoleWithWebIdentity
  ▼
github-actions-plan IAM role  (read-only: Describe/List/Get)
  │  used for: tofu plan in CI
  │  cannot: apply, destroy, or write anything

Spacelift (plan + apply runs)
  │  cross-account sts:AssumeRole + ExternalId
  ▼
spacelift-integration IAM role  (AdministratorAccess)
  │  used for: all Spacelift plan and apply runs
  │  scoped to: Spacelift's AWS account + integration ExternalId

EKS nodes (EC2)
  │  EC2 instance profile
  ▼
eks-node-role IAM role
  ├── AmazonEKSWorkerNodePolicy
  ├── AmazonEKS_CNI_Policy
  ├── AmazonEC2ContainerRegistryReadOnly
  └── cloudwatch-logs-read-for-alloy  (inline policy)

EBS CSI controller pod  (kube-system)
  │  IRSA — JWT token exchanged for temporary credentials
  ▼
eks-ebs-csi-role IAM role
  └── AmazonEBSCSIDriverPolicy
      (scoped to: system:serviceaccount:kube-system:ebs-csi-controller-sa)
```

The principle of least privilege is applied at each layer. The GitHub Actions plan role cannot create or delete resources. The node role carries only what is required for cluster operation plus Alloy's CloudWatch read. The EBS CSI role is scoped to a single service account via IRSA rather than being added to the node role (see [ADR-004](decisions/004-irsa-over-node-role.md)).

### Network isolation

```text
Internet
  │
  ▼
Internet Gateway
  │
  ▼
Public subnets  (NAT Gateway, NLBs)
  │
  │  NAT — outbound only
  ▼
Private subnets  (EKS nodes)
  │
  │  VPC CIDR only (port 443)
  ▼
EKS control plane (API server)
```

Nodes are in private subnets and have no public IPs. All internet egress from nodes goes through the NAT Gateway. The API server security group restricts HTTPS ingress to the VPC CIDR, meaning the API server is only reachable from within the network — external access goes through the public endpoint, which is restricted to specific CIDRs via `public_access_cidrs`.

### Policy enforcement (Spacelift)

Two layers of Spacelift policy protect production:

| Policy | Type | Effect |
| --- | --- | --- |
| `dev-plan` | PLAN | Warns on destructions and large blast radius. No hard blocks. |
| `prod-plan` | PLAN | Hard-blocks destruction of 8 protected resource types (EKS cluster, VPC, KMS key, IAM roles, subnets, NAT Gateway, IGW). Emergency override via run metadata. |
| `prod-approval` | APPROVAL | Requires 1 approval for standard runs, 2 for emergency destruction runs. Rejections always block. |

The emergency override is a deliberate escape hatch for situations where infrastructure genuinely must be destroyed. It is documented in [docs/runbooks/emergency-destroy.md](runbooks/emergency-destroy.md).

---

## Multi-Environment Strategy

| Setting | dev | prod |
| --- | --- | --- |
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` |
| Node instance type | `t3.medium` | `t3.large` |
| Node desired / max / min | 2 / 3 / 1 | 3 / 6 / 2 |
| Spacelift autodeploy | `true` | `false` |
| Plan policy | warn-only | hard blocks on protected types |
| Approval policy | none | 1 approval (2 for emergency) |

Environment configuration lives entirely in the `environments` variable in `stacks/spacelift/variables.tf`. Adding a new environment (e.g. `staging`) requires only a new entry there — the `setproduct` loop generates all stacks and dependencies automatically.

---

## CI/CD Workflow

```text
Pull request opened / updated
  │
  ├── opentofu-validate
  │     ├── fmt check
  │     ├── tofu validate (each stack, matrix)
  │     ├── opa fmt --check (Rego files)
  │     ├── make test-policies (OPA unit tests)
  │     └── tflint (AWS ruleset)
  │
  ├── opentofu-plan
  │     ├── plan network-dev, network-prod
  │     ├── plan eks-dev, eks-prod
  │     ├── plan eks-addons-dev, eks-addons-prod
  │     ├── plan kyverno-dev, kyverno-prod
  │     ├── plan argo-cd-dev, argo-cd-prod
  │     ├── plan prometheus-dev, prometheus-prod
  │     └── aggregate results → PR comment
  │
  ├── megalinter
  │     ├── YAML, JSON, Markdown linting
  │     ├── spell check
  │     ├── secret scanning (Gitleaks)
  │     ├── Trivy (IaC misconfig)
  │     ├── Checkov (IaC security)
  │     └── SARIF → GitHub Security tab
  │
  └── commitlint
        └── PR title must follow Conventional Commits

Merge to main
  └── Spacelift detects change → plans and applies affected stacks
        (dev: autodeploy=true, prod: requires approval)
```

Plans run without a Spacelift backend (`-backend=false`) and fetch cross-stack outputs from the live Spacelift API via `spacectl`. This means plan output reflects real infrastructure values rather than unknown placeholders.

---

## Architecture Decision Records

Significant design choices are documented as ADRs in [`docs/decisions/`](decisions/):

### Accepted

- [ADR-001: Spacelift over Atlantis](decisions/001-spacelift-over-atlantis.md)
- [ADR-002: Loki over CloudWatch Insights](decisions/002-loki-over-cloudwatch-insights.md)
- [ADR-003: Single NAT Gateway](decisions/003-single-nat-gateway.md)
- [ADR-004: IRSA over node role for EBS CSI](decisions/004-irsa-over-node-role.md)
- [ADR-005: ALB Ingress Controller over NLB per service](decisions/005-nlb-per-service-vs-alb-ingress.md)

### Open — Decision Pending

These decisions must be made before production go-live. Until they are resolved, the affected components are either absent or running in a degraded configuration.

| ADR | Topic | Blocks |
| --- | --- | --- |
| [ADR-006](decisions/006-argocd-app-repo.md) | ArgoCD application repository strategy | ArgoCD is deployed but watches nothing |
| [ADR-007](decisions/007-cluster-autoscaler-vs-karpenter.md) | Cluster Autoscaler vs. Karpenter vs. fixed sizing | Idle node costs |
| [ADR-008](decisions/008-secrets-management.md) | Secrets management for application workloads | Application workloads cannot receive secrets |
| [ADR-009](decisions/009-tls-and-ingress.md) | TLS termination and certificate management | Credentials in plaintext over the network |

---

## Runbooks

- [Initial Bootstrap](runbooks/initial-bootstrap.md) — First-time deployment from zero to running dev + prod
- [Bootstrap Troubleshooting](runbooks/bootstrap-troubleshooting.md) — Failure patterns, rollback procedure, and EKS/Spacelift contingencies
- [Emergency: Destroying Production Infrastructure](runbooks/emergency-destroy.md) — Override the prod-plan policy and destroy protected resources
