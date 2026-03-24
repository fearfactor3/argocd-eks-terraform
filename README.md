# OpenTofu EKS Cluster with Argo CD

This repository contains OpenTofu configurations to provision an Amazon EKS cluster, Argo CD for GitOps continuous delivery, and a kube-prometheus-stack for observability. Infrastructure is managed as independent stacks orchestrated by [Spacelift](https://spacelift.io/).

## Architecture

- **Two environments** — `dev` and `prod` — each with a fully isolated VPC and EKS cluster
- **VPC** with public and private subnets across multiple availability zones (per environment)
- **NAT Gateway** for private subnet internet egress
- **EKS cluster** (v1.32) with managed node groups deployed on private subnets
- **EKS managed add-ons**: vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver
- **KMS encryption** for EKS secrets at rest
- **Argo CD** deployed via Helm for GitOps workflows
- **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager) deployed via Helm for observability
- **Loki + Grafana Alloy** for log aggregation — VPC flow logs ship CloudWatch → Alloy → Loki → Grafana
- **Spacelift** manages stack dependencies, cross-stack output injection, and per-environment configuration

See [docs/architecture.md](docs/architecture.md) for the full system design, component breakdown, security model, and observability pipeline.

## Repository Structure

```bash
.
├── .github/
│   ├── linters/              # Linter configs (.tflint.hcl, .yamllint, .checkov.yaml, cspell.json, etc.)
│   ├── workflows/
│   │   ├── _tofu-plan-stack.yml  # Reusable workflow called by plan.yml
│   │   ├── cleanup-branches.yml  # Weekly stale branch cleanup
│   │   ├── commitlint.yml        # PR title conventional commit check
│   │   ├── mega-linter.yml       # MegaLinter (YAML, JSON, Markdown, Trivy, Checkov)
│   │   ├── plan.yml              # Per-stack tofu plan with PR comment
│   │   └── validate.yml          # fmt, validate, tflint, Rego policy tests
│   └── renovate.json         # Renovate dependency update configuration
├── modules/                  # Reusable OpenTofu modules
│   ├── argo-cd/              # Argo CD Helm release
│   ├── eks/                  # EKS cluster, node group, IAM roles, add-ons
│   ├── network/              # VPC, subnets, IGW, NAT Gateway, route tables
│   └── prometheus/           # kube-prometheus-stack Helm release
├── stacks/                   # Spacelift stacks (each deployed independently)
│   ├── iam/                  # GitHub Actions OIDC provider + plan role
│   ├── network/              # Deploys the network module
│   ├── eks/                  # Deploys the eks module (depends on network)
│   ├── argo-cd/              # Deploys Argo CD (depends on eks)
│   ├── prometheus/           # Deploys Prometheus stack (depends on eks)
│   └── spacelift/            # Spacelift stack definitions (meta-stack)
├── docs/                     # Additional documentation
│   ├── architecture.md       # System design, components, security model, observability pipeline
│   ├── setup.md              # Prerequisites and one-time developer setup
│   ├── development.md        # Daily workflow, hooks, dependency management
│   ├── bootstrap.md          # One-time GitHub + Spacelift infrastructure setup
│   ├── spacelift.md          # Policies, approval workflow, spacectl operations
│   ├── decisions/            # Architecture Decision Records (ADRs)
│   │   ├── 001-spacelift-over-atlantis.md
│   │   ├── 002-loki-over-cloudwatch-insights.md
│   │   ├── 003-single-nat-gateway.md
│   │   └── 004-irsa-over-node-role.md
│   └── runbooks/
│       └── emergency-destroy.md  # Production destruction procedure
├── .mega-linter.yml          # MegaLinter configuration
├── .pre-commit-config.yaml   # Pre-commit hooks
├── .regal/config.yaml        # Regal OPA linter configuration
├── .tflintignore             # tflint path exclusions
├── .trivyignore              # Trivy intentional exception list
├── cspell.json               # IDE spell-check stub (imports .github/linters/cspell.json)
└── Makefile                  # Local development targets
```

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.10.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with appropriate credentials
- [spacectl](https://github.com/spacelift-io/spacectl) (for local Spacelift interactions)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [Helm](https://helm.sh/docs/intro/install/) 3+ installed
- [tflint](https://github.com/terraform-linters/tflint) v0.61.0 (for local linting)
- [opa](https://www.openpolicyagent.org/docs/latest/#running-opa) (for policy tests and `opa-fmt` pre-commit hook)
- [pre-commit](https://pre-commit.com/) (for local hooks)
- [jq](https://jqlang.github.io/jq/) (for cross-stack output parsing)

See [docs/setup.md](docs/setup.md) for full installation instructions.

## Component Versions

| Component | Version |
| --- | --- |
| OpenTofu | >= 1.10.0 |
| AWS Provider | ~> 6.0 |
| Helm Provider | ~> 3.0 |
| Kubernetes Provider | ~> 3.0 |
| EKS Kubernetes | 1.32 (standard support) |
| vpc-cni Add-on | v1.20.4-eksbuild.2 |
| coredns Add-on | v1.11.4-eksbuild.2 |
| kube-proxy Add-on | v1.32.6-eksbuild.12 |
| aws-ebs-csi-driver Add-on | v1.56.0-eksbuild.1 |
| Argo CD Helm Chart | 9.4.1 (App v3.3.0) |
| kube-prometheus-stack Chart | 81.5.0 (Operator v0.88.1) |
| OPA | 1.14.1 |

## Stack Deployment Order

Stacks have explicit dependencies managed by Spacelift. Each environment (`dev`, `prod`) runs as an independent set of stacks:

```text
iam (shared, once per account)

network-dev → eks-dev → argo-cd-dev
                      → prometheus-dev

network-prod → eks-prod → argo-cd-prod
                        → prometheus-prod
```

The `spacelift` stack is a meta-stack that manages all app stacks as code, including dependencies and per-environment variable injection.

Cross-stack outputs (e.g., VPC ID from `network-<env>`, cluster endpoint from `eks-<env>`) are injected by Spacelift as `TF_VAR_*` environment variables into dependent stacks automatically.

## CI/CD

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `megalinter` | PR → main | YAML, JSON, Markdown, spelling, secrets, Trivy, Checkov — SARIF uploaded to GitHub Security tab |
| `opentofu-validate` | PR → main (stacks/modules changed) | `tofu fmt`, `tofu validate` per stack, `tflint`, Rego policy tests and format check |
| `opentofu-plan` | PR → main (stacks/modules changed) | Per-stack × per-environment plan; results aggregated in a PR comment |
| `commitlint` | PR → main | Enforce conventional commit format on PR title |
| `cleanup-branches` | Weekly (Mon 06:00 UTC) | Delete merged branches older than 14 days |

## Local Development

- [docs/setup.md](docs/setup.md) — prerequisites and one-time developer setup
- [docs/development.md](docs/development.md) — daily workflow, pre-commit hooks, dependency management
- [docs/bootstrap.md](docs/bootstrap.md) — one-time GitHub + Spacelift infrastructure setup
- [docs/spacelift.md](docs/spacelift.md) — policies, approval workflow, spacectl operations

Install pre-commit hooks on first checkout:

```sh
pre-commit install
```

Common Makefile targets:

```sh
make help          # List all targets
make init          # tofu init for all stacks
make validate      # tofu validate for all stacks
make fmt           # tofu fmt -recursive
make plan-network  # Plan the network stack
make plan-eks      # Plan the eks stack
make plan-argo-cd  # Plan the argo-cd stack
make plan-prometheus # Plan the prometheus stack
make clean         # Remove all .terraform dirs and lock files
```

To target a specific stack directly:

```sh
tofu -chdir=stacks/network init
tofu -chdir=stacks/network plan
tofu -chdir=stacks/network apply
```

## Stacks

### iam

Provisions the GitHub Actions OIDC provider and a least-privilege plan role used by the `opentofu-plan` workflow. Deploy once per AWS account.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `github_org` | GitHub organisation name | — |
| `github_repo` | GitHub repository name | — |

### network

Sets up the VPC, public and private subnets, internet gateway, NAT gateway with Elastic IP, and route tables.

Per-environment values (`vpc_cidr`, `public_subnets`, `private_subnets`, `cluster_name`) are injected by Spacelift from the `spacelift` stack's `environments` variable — no manual variable passing required.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `environment` | Environment name (e.g. `dev`, `prod`) | — injected by Spacelift |
| `project_name` | Project name for resource naming | `argocd` |
| `cluster_name` | EKS cluster name (for subnet discovery tags) | — injected by Spacelift |
| `vpc_cidr` | CIDR block for the VPC | — injected by Spacelift |
| `public_subnets` | Public subnet CIDR blocks | — injected by Spacelift |
| `private_subnets` | Private subnet CIDR blocks | — injected by Spacelift |
| `azs` | Availability zones | `["us-east-1a", "us-east-1b"]` |

### eks

Creates the EKS cluster with managed node groups on private subnets, IAM roles and policies, KMS encryption for secrets, full control plane logging, and managed add-ons (vpc-cni, coredns, kube-proxy).

Cross-stack inputs are injected by Spacelift from the `network` stack.

Per-environment values (`cluster_name`, `environment`, `node_group_*`) are injected by Spacelift from the `spacelift` stack's `environments` variable. Cross-stack inputs (`vpc_id`, `subnet_ids`) are injected by Spacelift from the `network-<env>` stack.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `environment` | Environment name (e.g. `dev`, `prod`) | — injected by Spacelift |
| `cluster_name` | EKS cluster name | — injected by Spacelift |
| `cluster_version` | Kubernetes version | `1.32` |
| `node_group_desired_capacity` | Desired node count | — injected by Spacelift |
| `node_group_max_capacity` | Maximum node count | — injected by Spacelift |
| `node_group_min_capacity` | Minimum node count | — injected by Spacelift |
| `node_group_instance_types` | Node instance types | — injected by Spacelift |
| `public_access_cidrs` | CIDRs permitted to reach the public API endpoint | — |
| `vpc_id` | VPC ID (from `network-<env>` stack) | — injected by Spacelift |
| `subnet_ids` | Private subnet IDs (from `network-<env>` stack) | — injected by Spacelift |
| `vpc_cni_addon_version` | vpc-cni managed add-on version | `v1.20.4-eksbuild.2` |
| `coredns_addon_version` | coredns managed add-on version | `v1.11.4-eksbuild.2` |
| `kube_proxy_addon_version` | kube-proxy managed add-on version | `v1.32.6-eksbuild.12` |
| `ebs_csi_addon_version` | aws-ebs-csi-driver managed add-on version | `v1.56.0-eksbuild.1` |

### argo-cd

Deploys Argo CD via Helm with an NLB service. Cross-stack inputs are injected by Spacelift from the `eks-<env>` stack.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `environment` | Environment name (e.g. `dev`, `prod`) | — injected by Spacelift |
| `argocd_chart_version` | Argo CD Helm chart version | `9.4.1` |
| `eks_cluster_name` | EKS cluster name (from `eks-<env>` stack) | — injected by Spacelift |
| `eks_cluster_endpoint` | EKS API endpoint (from `eks-<env>` stack) | — injected by Spacelift |
| `cluster_ca_certificate` | Base64-encoded CA certificate (from `eks-<env>` stack) | — injected by Spacelift |

Outputs: `argocd_release_namespace`, `argocd_server_load_balancer`, initial admin password retrieval command, kubeconfig update command.

### prometheus

Deploys the kube-prometheus-stack (Prometheus, Grafana, Alertmanager) via Helm. Grafana uses an NLB service with a 50 Gi persistent volume; Prometheus uses a 50 Gi persistent volume. A `gp3` storage class is created as the cluster default. Cross-stack inputs are injected by Spacelift from the `eks-<env>` stack.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `environment` | Environment name (e.g. `dev`, `prod`) | — injected by Spacelift |
| `prometheus_chart_version` | kube-prometheus-stack Helm chart version | `81.5.0` |
| `eks_cluster_name` | EKS cluster name (from `eks-<env>` stack) | — injected by Spacelift |
| `eks_cluster_endpoint` | EKS API endpoint (from `eks-<env>` stack) | — injected by Spacelift |
| `cluster_ca_certificate` | Base64-encoded CA certificate (from `eks-<env>` stack) | — injected by Spacelift |

Outputs: `prometheus_release_namespace`, `grafana_load_balancer`, Grafana admin password retrieval command.

### spacelift

Manages all Spacelift stacks as code. Defines the cross-product of environments × stack types, wires stack dependencies, and injects per-environment configuration as `TF_VAR_*` environment variables into each stack.

Per-environment defaults are controlled via the `environments` variable in `stacks/spacelift/variables.tf`:

| Setting | dev | prod |
| --- | --- | --- |
| Instance type | `t3.medium` | `t3.large` |
| Desired nodes | `2` | `3` |
| Max nodes | `3` | `6` |
| Min nodes | `1` | `2` |
| Autodeploy | `true` | `false` |

Override at apply time with `-var` flags or Spacelift environment variables.

## Post-Deployment

Connect to a cluster (substitute `dev` or `prod`):

```sh
aws eks update-kubeconfig --region us-east-1 --name argocd-dev
# or
aws eks update-kubeconfig --region us-east-1 --name argocd-prod
```

Retrieve the Argo CD admin password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Retrieve the Grafana admin password:

```sh
kubectl -n prometheus get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

## Commit Message Format

Commits and PR titles must follow [Conventional Commits](https://www.conventionalcommits.org/) and are enforced by commitlint (pre-commit) and the PR title check (GitHub Actions).

Format: `type(scope): short description`

### Allowed types

| Type | When to use |
| --- | --- |
| `feat` | New feature or resource |
| `fix` | Bug fix or misconfiguration correction |
| `refactor` | Code restructuring with no behaviour change |
| `chore` | Maintenance, version bumps, cleanup |
| `ci` | Changes to GitHub Actions workflows or MegaLinter config |
| `docs` | README or documentation only |
| `style` | Formatting, whitespace (no logic change) |
| `test` | Adding or updating tests |

### Allowed scopes

| Scope | Covers |
| --- | --- |
| `network` | VPC, subnets, NAT gateway, route tables |
| `eks` | EKS cluster, node group, IAM roles, add-ons |
| `argo-cd` | Argo CD Helm release |
| `prometheus` | kube-prometheus-stack Helm release |
| `iam` | GitHub Actions OIDC provider and plan role |
| `spacelift` | Spacelift stack definitions |
| `ci` | GitHub Actions workflows and MegaLinter config |
| `deps` | Dependency updates (Renovate, pre-commit hooks) |
| `docs` | README and documentation |
| `modules` | Cross-cutting changes spanning multiple modules |
| `stacks` | Cross-cutting changes spanning multiple stacks |

### Examples

```sh
feat(eks): add KMS key policy for secrets encryption
fix(network): restrict default security group egress
ci(megalinter): move trivy and checkov into MegaLinter
chore(deps): bump setup-opentofu to v2.0.1
docs(readme): update repository structure tree
refactor(modules): add required_providers blocks to all modules
```

## Cleanup

Spacelift manages destroy runs — use `spacectl` or the Spacelift UI to trigger them in reverse dependency order (argo-cd/prometheus → eks → network). For production environments, see the [Emergency: Destroying Production Infrastructure](docs/runbooks/emergency-destroy.md) runbook which covers the required approval flow and override flag.

For the IAM stack (deployed outside Spacelift):

```sh
tofu -chdir=stacks/iam destroy
```
