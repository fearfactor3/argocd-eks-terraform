# Bootstrap

One-time setup steps to make CI/CD workflows functional. Complete these steps in order — each depends on the previous.

---

## Step 1: Apply the IAM Stack

The `stacks/iam` stack creates the GitHub Actions OIDC provider and a read-only plan
role. It runs outside Spacelift and must be applied manually first.

```sh
cd stacks/iam
tofu init
tofu plan -var="github_org=<your-github-user-or-org>" -var="github_repo=argocd-eks-terraform"
tofu apply -var="github_org=<your-github-user-or-org>" -var="github_repo=argocd-eks-terraform"
```

Set the role ARN as a GitHub secret:

```sh
gh secret set AWS_ROLE_ARN --body "$(tofu output -raw github_actions_plan_role_arn)"
```

The role is scoped to `pull_request` events only with read-only permissions. No write
access is granted — plan only.

---

## Step 2: Configure GitHub Secrets and Variables

```sh
gh secret set SPACELIFT_API_KEY_ID     --body "<key-id>"
gh secret set SPACELIFT_API_KEY_SECRET --body "<key-secret>"
gh variable set AWS_REGION             --body "us-east-1"
gh variable set SPACELIFT_API_URL      --body "https://<org>.app.spacelift.io"
```

See [Spacelift](spacelift.md) for instructions on creating the API key.

---

## Step 3: Bootstrap the Spacelift Stack

The `stacks/spacelift` stack defines all application stacks and their dependencies as
code. It must be bootstrapped manually once:

1. In the Spacelift UI, create a new stack manually:
   - **Repository:** `argocd-eks-terraform`
   - **Project root:** `stacks/spacelift`
   - **Branch:** `main`
   - **Tool:** OpenTofu
   - **Autodeploy:** enabled — the management stack must apply automatically to create the app stacks

1. Apply the stack from the Spacelift UI. This creates all app stacks (`iam`, `network-dev`,
   `network-prod`, `eks-dev`, `eks-prod`, `argo-cd-dev`, `argo-cd-prod`, `prometheus-dev`,
   `prometheus-prod`) and wires their dependencies.

   Dev stacks have autodeploy enabled — merges to `main` apply automatically.
   Prod stacks have autodeploy disabled — every run stops at the approval gate before applying.

   > **Future:** Add a Spacelift plan policy to require management approval when changes
   > exceed a defined risk threshold (e.g. any resource destructions, or more than N
   > resources changing). This gates high-impact applies without blocking routine changes.

1. Once applied, Spacelift manages all subsequent runs. Merges to `main` trigger
   apply runs in dependency order automatically.

> **Note:** Until this step is complete, the `plan` CI workflow will succeed for
> `network` (no dependencies) but dependent stacks (`eks`, `argo-cd`, `prometheus`)
> will fail to plan due to missing cross-stack outputs.

---

## Step 4: Ongoing — Spacelift Manages Everything

After bootstrapping, the workflow is:

- **Pull request** → GitHub Actions runs `tofu plan` for every stack × environment. Cross-stack outputs are fetched live from Spacelift via `spacectl` and passed as `-var` flags so the plan reflects actual deployed state.
- **Merge to `main`** → Spacelift triggers `tofu apply` runs per environment in dependency order:
  1. `network-{dev,prod}`
  2. `eks-{dev,prod}` (after network)
  3. `argo-cd-{dev,prod}` and `prometheus-{dev,prod}` (after eks, in parallel)

Dev stacks apply automatically. Prod stacks wait for approval before applying (see [Spacelift: Production Approval Workflow](spacelift.md#production-approval-workflow)).

Spacelift injects outputs from upstream stacks as `TF_VAR_*` environment variables
into dependent stacks automatically — no manual variable passing required.

---

## Secrets Reference

| Secret | Description |
| --- | --- |
| `AWS_ROLE_ARN` | IAM role ARN output from `stacks/iam` — see [Step 1](#step-1-apply-the-iam-stack) |
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
