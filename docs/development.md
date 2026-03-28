# Development

Day-to-day development workflow for this repository.

---

## Daily Workflow

```sh
git checkout -b feat/eks-add-kms-key-policy

# Format and run all static checks before committing
make fmt
make lint

# Commit — commitlint enforces conventional format on every commit
git commit -m "feat(eks): add KMS key policy for secrets encryption"
```

If commitlint rejects the message it prints the violated rules and links to the
commit message format section of the README.

On pull request open:

- `commitlint` validates the PR title
- `opentofu-validate` runs `fmt`, `validate`, `tflint`, and Rego policy tests (triggers on `stacks/**`, `modules/**`)
- `opentofu-plan` posts a per-stack plan comment for every stack × environment (triggers on `stacks/**`, `modules/**`)
- `megalinter` runs YAML, JSON, Markdown, spelling, Trivy, and Checkov

All checks must pass before merging.

---

## Local Stack Operations

| Target | What it does |
| ------ | ------------ |
| `make lint` | fmt-check + tflint + policy format + markdownlint (no init required) |
| `make test` | All of `lint` plus module tests and policy unit tests |
| `make plan-dev` | Plan all environment stacks with dev.tfvars |
| `make plan-prod` | Plan all environment stacks with prod.tfvars |
| `make plan-spacelift` | Plan the Spacelift management stack |
| `make validate` | Schema-validate all stacks (requires `tofu init` first) |

Local plans run against empty state — useful for validating configuration but do
not reflect the actual delta against deployed infrastructure.

```sh
make plan-dev
make plan-prod
```

Or directly for a single stack:

```sh
tofu -chdir=stacks/network init -backend=false
tofu -chdir=stacks/network plan -var-file=dev.tfvars
```

---

## Pre-commit Hooks

| Hook | What it checks |
| --- | --- |
| `check-yaml` / `check-json` | File syntax |
| `detect-aws-credentials` | No hardcoded AWS keys |
| `no-commit-to-branch` | Cannot commit directly to `main` |
| `opa-fmt` | OPA Rego formatting |
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
- OPA version (`validate.yml`)

Review and merge Renovate PRs regularly. All checks must pass before merging.

---

## Branch Protection (main)

Configure these settings under **Settings → Branches → main** in GitHub:

| Setting | Value |
| ------- | ----- |
| Require a pull request before merging | Enabled |
| Required approvals | 1 (raise to 2 for team use) |
| Dismiss stale reviews on new commits | Enabled |
| Require status checks to pass | Enabled |
| Require branches to be up to date | Enabled |
| Allow force pushes | Disabled |
| Allow deletions | Disabled |

**Required status checks** (add each by name):

| Check name | Workflow |
| ---------- | -------- |
| `Detect changes` | `opentofu-validate` |
| `Format check` | `opentofu-validate` |
| `Validate (argo-cd)` | `opentofu-validate` |
| `Validate (eks)` | `opentofu-validate` |
| `Validate (eks-addons)` | `opentofu-validate` |
| `Validate (iam)` | `opentofu-validate` |
| `Validate (network)` | `opentofu-validate` |
| `Validate (prometheus)` | `opentofu-validate` |
| `Validate (spacelift)` | `opentofu-validate` |
| `Test Rego policies` | `opentofu-validate` |
| `Test modules` | `opentofu-validate` |
| `tflint` | `opentofu-validate` |
| `plan-summary` | `opentofu-plan` |
| `commitlint` | `commitlint` |
| `MegaLinter` | `megalinter` |

**Merge strategy:** Squash merge only. Each PR lands as a single conventional commit on `main`, which Spacelift uses as the trigger for automated runs.
