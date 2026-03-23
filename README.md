# OpenTofu EKS Cluster with Argo CD

This repository contains OpenTofu configurations to provision an Amazon EKS cluster, Argo CD for GitOps continuous delivery, and a kube-prometheus-stack for observability. Infrastructure is managed as independent stacks orchestrated by [Spacelift](https://spacelift.io/).

## Architecture

- **VPC** with public and private subnets across multiple availability zones
- **NAT Gateway** for private subnet internet egress
- **EKS cluster** (v1.32) with managed node groups deployed on private subnets
- **EKS managed add-ons**: vpc-cni, coredns, kube-proxy
- **KMS encryption** for EKS secrets at rest
- **Argo CD** deployed via Helm for GitOps workflows
- **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager) deployed via Helm for observability
- **Spacelift** manages stack dependencies and cross-stack output injection

## Repository Structure

```bash
.
├── .github/
│   ├── linters/              # Linter configs (.tflint.hcl, .yamllint, cspell.json, etc.)
│   ├── workflows/            # GitHub Actions CI/CD workflows
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
│   └── operating-guide.md    # Day-to-day operating procedures
├── .mega-linter.yml          # MegaLinter configuration
├── .pre-commit-config.yaml   # Pre-commit hooks
├── .tflintignore             # tflint exclusions
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
- [pre-commit](https://pre-commit.com/) (for local hooks)
- [jq](https://jqlang.github.io/jq/) (for cross-stack output parsing)

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

## Stack Deployment Order

Stacks have explicit dependencies managed by Spacelift. Deploy in this order:

```text
iam → network → eks → argo-cd
                    → prometheus
```

The `spacelift` stack is a meta-stack that manages the other stacks as code.

Cross-stack outputs (e.g., VPC ID from `network`, cluster endpoint from `eks`) are injected by Spacelift as `TF_VAR_*` environment variables into dependent stacks.

## CI/CD

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `megalinter` | push/PR → main | YAML, JSON, Markdown, spelling, secrets, Trivy, Checkov — SARIF uploaded to GitHub Security tab |
| `opentofu-validate` | PR → main (stacks/modules changed) | `tofu fmt`, `tofu validate` per stack, `tflint` |
| `opentofu-plan` | PR → main (stacks/modules changed) | Per-stack plan with combined PR table comment and gate enforcement |
| `commitlint` | PR → main | Enforce conventional commit PR titles |

## Local Development

See the [Operating Guide](docs/operating-guide.md) for full day-to-day procedures including Spacelift authentication, stack operations, and troubleshooting.

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

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `project_name` | Project name for resource naming | `argocd` |
| `cluster_name` | EKS cluster name (for subnet discovery tags) | `argocd-cluster` |
| `vpc_cidr` | CIDR block for the VPC | `10.0.0.0/16` |
| `public_subnets` | Public subnet CIDR blocks | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `private_subnets` | Private subnet CIDR blocks | `["10.0.3.0/24", "10.0.4.0/24"]` |
| `azs` | Availability zones | `["us-east-1a", "us-east-1b"]` |

### eks

Creates the EKS cluster with managed node groups on private subnets, IAM roles and policies, KMS encryption for secrets, full control plane logging, and managed add-ons (vpc-cni, coredns, kube-proxy).

Cross-stack inputs are injected by Spacelift from the `network` stack.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `cluster_name` | EKS cluster name | `argocd-cluster` |
| `cluster_version` | Kubernetes version | `1.32` |
| `environment` | Environment name | `Dev` |
| `node_group_desired_capacity` | Desired node count | `2` |
| `node_group_max_capacity` | Maximum node count | `3` |
| `node_group_min_capacity` | Minimum node count | `1` |
| `node_group_instance_types` | Node instance types | `["t3.medium"]` |
| `public_access_cidrs` | CIDRs permitted to reach the public API endpoint | — |
| `vpc_id` | VPC ID (from network stack) | — |
| `subnet_ids` | Private subnet IDs (from network stack) | — |
| `vpc_cni_addon_version` | vpc-cni managed add-on version | `v1.20.4-eksbuild.2` |
| `coredns_addon_version` | coredns managed add-on version | `v1.11.4-eksbuild.2` |
| `kube_proxy_addon_version` | kube-proxy managed add-on version | `v1.32.6-eksbuild.12` |
| `ebs_csi_addon_version` | aws-ebs-csi-driver managed add-on version | `v1.56.0-eksbuild.1` |

### argo-cd

Deploys Argo CD via Helm. Cross-stack inputs are injected by Spacelift from the `eks` stack.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `argocd_chart_version` | Argo CD Helm chart version | `9.4.1` |
| `eks_cluster_name` | EKS cluster name (from eks stack) | — |
| `eks_cluster_endpoint` | EKS API endpoint (from eks stack) | — |
| `cluster_ca_certificate` | Base64-encoded CA certificate (from eks stack) | — |

### prometheus

Deploys the kube-prometheus-stack (Prometheus, Grafana, Alertmanager) via Helm. Cross-stack inputs are injected by Spacelift from the `eks` stack.

| Variable | Description | Default |
| --- | --- | --- |
| `aws_region` | AWS region | `us-east-1` |
| `prometheus_chart_version` | kube-prometheus-stack Helm chart version | `81.5.0` |
| `eks_cluster_name` | EKS cluster name (from eks stack) | — |
| `eks_cluster_endpoint` | EKS API endpoint (from eks stack) | — |
| `cluster_ca_certificate` | Base64-encoded CA certificate (from eks stack) | — |

### spacelift

Manages all Spacelift stacks as code, including stack definitions, dependencies, and environment variable mappings for cross-stack output injection.

## Post-Deployment

Connect to the cluster:

```sh
aws eks update-kubeconfig --region <your-region> --name <cluster-name>
```

Retrieve the Argo CD admin password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
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

Destroy stacks in reverse dependency order:

```sh
tofu -chdir=stacks/argo-cd destroy
tofu -chdir=stacks/prometheus destroy
tofu -chdir=stacks/eks destroy
tofu -chdir=stacks/network destroy
tofu -chdir=stacks/iam destroy
```
