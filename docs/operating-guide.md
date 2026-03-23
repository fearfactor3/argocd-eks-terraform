# Operating Guide

See the [README](../README.md) for architecture overview, stack variables, component versions, and commit message format.

---

## Initial Setup

### Prerequisites

**Developers:**

| Tool | Install |
| --- | --- |
| `pre-commit` | `brew install pre-commit` |
| `node` + `npm` | `brew install node` (required for commitlint hook) |
| `opentofu` | `brew install opentofu` (required for `terraform_fmt` hook) |
| `aws` CLI | `brew install awscli` |

**DevOps / Platform Engineers:**

All of the above, plus:

| Tool | Install |
| --- | --- |
| `tflint v0.61.0` | `brew install tflint` |
| `spacectl` | `brew install spacelift-io/tap/spacectl` |
| `kubectl` | `brew install kubectl` |
| `helm` | `brew install helm` |

---

Clone the repository and install pre-commit hooks:

```sh
git clone https://github.com/fearfactor3/argocd-eks-terraform
cd argocd-eks-terraform
pre-commit install
```

This installs both `pre-commit` and `commit-msg` hook types. The `commit-msg` hook
runs commitlint on every commit to enforce conventional commit format.

Initialize tflint plugins (platform engineers only):

```sh
tflint --init --config .github/linters/.tflint.hcl
```

### Signed commits

The `main` branch requires all commits to be signed. Configure Git to sign commits
with your GPG or SSH key before opening a pull request.

**GPG:**

```sh
gpg --list-secret-keys --keyid-format=long
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

**SSH (Git >= 2.34):**

```sh
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Register the key in GitHub under **Settings → SSH and GPG keys → New signing key**.
Unsigned commits will be blocked from merging to `main`.

---

## Daily Development Workflow

```sh
git checkout -b feat/eks-add-kms-key-policy

# Format and validate before committing
make fmt
make validate

# Commit — commitlint enforces conventional format on every commit
git commit -m "feat(eks): add KMS key policy for secrets encryption"
```

If commitlint rejects the message it prints the violated rules and links to the
commit message format section of the README.

On pull request open:

- `commitlint` validates the PR title
- `opentofu-validate` runs `fmt`, `validate`, and `tflint` (triggers on `stacks/**`, `modules/**`)
- `opentofu-plan` posts a per-stack plan table comment (triggers on `stacks/**`, `modules/**`)
- `megalinter` runs file-type linting, Trivy, and Checkov

All checks must pass before merging.

---

## Spacelift

Spacelift manages state, triggers runs on merge to `main`, and injects cross-stack
outputs as `TF_VAR_*` environment variables into dependent stacks.

### Authenticate spacectl

```sh
spacectl profile login --endpoint https://<org>.app.spacelift.io
```

### List stack outputs

```sh
spacectl stack output list --id network --format json
spacectl stack output list --id eks --format json
```

### Trigger a manual run

```sh
spacectl stack run trigger --id eks
```

---

## Local Stack Operations

Local plans run against empty state — useful for validating configuration but do
not reflect the actual delta against deployed infrastructure.

```sh
make plan-network
make plan-eks
make plan-argo-cd
make plan-prometheus
```

Or directly:

```sh
tofu -chdir=stacks/network init -backend=false
tofu -chdir=stacks/network plan
```

---

## Pre-commit Hooks

| Hook | What it checks |
| --- | --- |
| `check-yaml` / `check-json` | File syntax |
| `detect-aws-credentials` | No hardcoded AWS keys |
| `no-commit-to-branch` | Cannot commit directly to `main` |
| `terraform_fmt` | OpenTofu formatting |
| `terraform_tflint` | Lint rules (naming, required providers) |
| `commitlint` | Conventional commit message format |

Run all hooks manually against the full codebase:

```sh
pre-commit run --all-files
```

---

## Dependency Management

[Renovate](../.github/renovate.json) opens PRs automatically for:

- OpenTofu provider versions (`stacks/*/versions.tf`)
- GitHub Actions SHA pins (`workflows/*.yml`)
- pre-commit hook revisions (`.pre-commit-config.yaml`)
- Argo CD Helm chart version (`stacks/argo-cd/variables.tf`)
- kube-prometheus-stack Helm chart version (`stacks/prometheus/variables.tf`)
- tflint version (`validate.yml`)

Review and merge Renovate PRs regularly. All checks must pass before merging.

---

## GitHub Repository Configuration

The following must be configured before CI/CD workflows are functional.

### Secrets

| Secret | Description |
| --- | --- |
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC authentication |
| `SPACELIFT_API_KEY_ID` | Spacelift API key ID for spacectl |
| `SPACELIFT_API_KEY_SECRET` | Spacelift API key secret for spacectl |

### Variables

| Variable | Description |
| --- | --- |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `SPACELIFT_API_URL` | Spacelift API endpoint (e.g. `https://<org>.app.spacelift.io`) |

### Branch protection

The following ruleset is active on `main`:

- Require a pull request before merging (no direct pushes)
- Require status checks: `MegaLinter`, `Format check`, `Validate (*)`, `tflint`, `PR title`, `plan-summary`
- Require branches to be up to date before merging
- Require signed commits (GPG or SSH — see [Signed commits](#signed-commits))
- Require linear history (squash or merge commits only, no rebase)
- Block force pushes and branch deletion
