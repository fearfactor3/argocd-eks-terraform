# Setup

One-time setup steps for every developer working on this repository.

---

## Prerequisites

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
| `opa` | `brew install opa` (required for `opa-fmt` hook and policy tests) |
| `spacectl` | `brew install spacelift-io/tap/spacectl` |
| `kubectl` | `brew install kubectl` |
| `helm` | `brew install helm` |

---

## Clone and Install Hooks

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

---

## Signed Commits

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
