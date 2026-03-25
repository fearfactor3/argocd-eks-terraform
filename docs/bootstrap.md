# Bootstrap

One-time setup steps to make CI/CD workflows functional. Complete these steps in order — each depends on the previous.

---

## Step 1: Configure GitHub Secrets and Variables

```sh
gh secret set SPACELIFT_API_KEY_ID     --body "<key-id>"
gh secret set SPACELIFT_API_KEY_SECRET --body "<key-secret>"
gh variable set AWS_REGION             --body "us-east-1"
gh variable set SPACELIFT_API_URL      --body "https://<org>.app.spacelift.io"
```

See [Spacelift](spacelift.md) for instructions on creating the API key.

---

## Step 2: Bootstrap the Spacelift Management Stack

The `stacks/spacelift` stack manages all other stacks as code. It must be created manually once in the Spacelift UI, then triggered to run.

### 2a — Create the management stack

In the Spacelift UI, create a new stack:

- **Repository:** `argocd-eks-terraform`
- **Project root:** `stacks/spacelift`
- **Branch:** `main`
- **Tool:** OpenTofu
- **Administrative:** enabled (required to create and manage other stacks)
- **Autodeploy:** enabled

### 2b — Set the required environment variable

In the management stack's **Environment** tab, add:

| Name | Value | Secret |
| --- | --- | --- |
| `TF_VAR_repository` | `argocd-eks-terraform` | No |

### 2c — Add bootstrap AWS credentials (first run only)

The management stack must create an IAM role (`spacelift-integration`) on its first apply so all app stacks have AWS credentials. Set them on the **management stack only** — app stacks (`network-dev`, `eks-dev`, etc.) get credentials automatically via the integration once it is created.

```sh
spacectl stack environment setvar \
  -id argocd-eks-terraform \
  --write-only \
  AWS_ACCESS_KEY_ID \
  "$(aws configure get aws_access_key_id)"

spacectl stack environment setvar \
  -id argocd-eks-terraform \
  --write-only \
  AWS_SECRET_ACCESS_KEY \
  "$(aws configure get aws_secret_access_key)"
```

The `$(aws configure get ...)` subshells pull values from your local `~/.aws/credentials`. If you use a named profile, prefix with `AWS_PROFILE=<profile>`. To use a temporary IAM user instead, replace the subshells with the literal key values.

> These are removed after the first successful apply — see step 2d.

### 2d — Trigger the first run

Trigger the management stack from the UI. On success it creates:

- All app stacks: `iam`, `network-dev/prod`, `eks-dev/prod`, `eks-addons-dev/prod`, `argo-cd-dev/prod`, `prometheus-dev/prod`
- The `spacelift-integration` IAM role in AWS (assumed by all Spacelift runs)
- Stack dependencies, cross-stack output references, and plan/approval policies

**After the run completes:** remove the bootstrap credentials — they are no longer needed:

```sh
spacectl stack environment delete \
  -id argocd-eks-terraform \
  AWS_ACCESS_KEY_ID

spacectl stack environment delete \
  -id argocd-eks-terraform \
  AWS_SECRET_ACCESS_KEY
```

### 2e — Apply the IAM stack and set AWS_ROLE_ARN

The `iam` stack creates the GitHub Actions OIDC provider and read-only plan role used by CI. Trigger it from the Spacelift UI, then set the output as a GitHub secret:

```sh
gh secret set AWS_ROLE_ARN --body "<role-arn-from-iam-stack-outputs>"
```

The role ARN is visible in the `iam` stack's **Outputs** tab in Spacelift after it applies.

---

## Step 3: Ongoing — Spacelift Manages Everything

After bootstrapping, the workflow is:

- **Pull request** → GitHub Actions runs `tofu plan` for every stack × environment. Cross-stack outputs are fetched live from Spacelift via `spacectl` and passed as `-var` flags so the plan reflects actual deployed state.
- **Merge to `main`** → Spacelift triggers `tofu apply` runs per environment in dependency order:
  1. `network-{dev,prod}`
  2. `eks-{dev,prod}` (after network)
  3. `eks-addons-{dev,prod}` (after eks)
  4. `argo-cd-{dev,prod}` and `prometheus-{dev,prod}` (after eks-addons, in parallel)

Dev stacks apply automatically. Prod stacks wait for approval before applying (see [Spacelift: Production Approval Workflow](spacelift.md#production-approval-workflow)).

Spacelift injects outputs from upstream stacks as `TF_VAR_*` environment variables
into dependent stacks automatically — no manual variable passing required.

---

## Secrets Reference

| Secret | Description |
| --- | --- |
| `AWS_ROLE_ARN` | IAM role ARN output from `stacks/iam` — see [Step 2e](#2e--apply-the-iam-stack-and-set-aws_role_arn) |
| `SPACELIFT_API_KEY_ID` | Spacelift API key ID for spacectl |
| `SPACELIFT_API_KEY_SECRET` | Spacelift API key secret for spacectl |

## Variables Reference

| Variable | Description |
| --- | --- |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `SPACELIFT_API_URL` | Spacelift API endpoint (e.g. `https://<org>.app.spacelift.io`) |

---

## Branch Protection

The following ruleset is active on `main`:

- Require a pull request before merging (no direct pushes)
- Require status checks: `MegaLinter`, `Format check`, `Validate (*)`, `tflint`, `Test Rego policies`, `PR title`, `plan-summary`
- Require branches to be up to date before merging
- Require signed commits (GPG or SSH — see [Signed commits](setup.md#signed-commits))
- Require linear history (squash or merge commits only, no rebase)
- Block force pushes and branch deletion
