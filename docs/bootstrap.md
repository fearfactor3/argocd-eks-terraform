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

### 2b — Run the first apply locally

The management stack creates an IAM role (`spacelift-integration`) that all app stacks use for AWS credentials. Running this apply locally avoids IAM propagation race conditions that occur when the apply runs inside Spacelift for the first time.

Your local AWS credentials must have `AdministratorAccess`. Your Spacelift API key must have admin permissions on the account.

```sh
export SPACELIFT_API_KEY_ENDPOINT=https://<org>.app.spacelift.io
export SPACELIFT_API_KEY_ID=<key-id>
export SPACELIFT_API_KEY_SECRET=<key-secret>

cd stacks/spacelift
tofu init
tofu apply -var="repository=argocd-eks-terraform"
```

On success this creates:

- All app stacks: `iam`, `network-dev/prod`, `eks-dev/prod`, `eks-addons-dev/prod`, `argo-cd-dev/prod`, `prometheus-dev/prod`
- The `spacelift-integration` IAM role in AWS (assumed by all Spacelift runs)
- Stack dependencies, cross-stack output references, and plan/approval policies

**Upload the state to Spacelift** so subsequent runs are consistent with what was applied locally:

```sh
spacectl stack state upload -id argocd-eks-terraform < terraform.tfstate
rm terraform.tfstate terraform.tfstate.backup
```

From this point on, all runs are driven by Spacelift on merge to `main` — no local applies needed.

### 2c — Apply the IAM stack and set AWS_ROLE_ARN

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
| `AWS_ROLE_ARN` | IAM role ARN output from `stacks/iam` — see [Step 2c](#2c--apply-the-iam-stack-and-set-aws_role_arn) |
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
