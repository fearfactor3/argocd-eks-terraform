# Development

Day-to-day development workflow for this repository.

---

## Daily Workflow

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
- `opentofu-validate` runs `fmt`, `validate`, `tflint`, and Rego policy tests (triggers on `stacks/**`, `modules/**`)
- `opentofu-plan` posts a per-stack plan comment for every stack × environment (triggers on `stacks/**`, `modules/**`)
- `megalinter` runs YAML, JSON, Markdown, spelling, Trivy, and Checkov

All checks must pass before merging.

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
