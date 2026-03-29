# Runbook: Bootstrap Troubleshooting

Common failures encountered during the initial bootstrap and how to resolve them. For the happy-path deployment procedure see [initial-bootstrap.md](initial-bootstrap.md).

---

## Rollback Procedure

### When to rollback

- Any stack stuck in `Failed` for more than 10 minutes with no progress
- `kubectl get nodes` shows `NotReady` after 25 minutes
- ArgoCD or Prometheus pods not reaching `Running` after 10 minutes

### How to rollback

Destroy in reverse dependency order:

```bash
# Via Spacelift Tasks (preferred) — reverse dependency order
spacectl stack task --id prometheus-dev    -- tofu destroy -auto-approve
spacectl stack task --id argo-cd-dev      -- tofu destroy -auto-approve
spacectl stack task --id eks-addons-dev   -- tofu destroy -auto-approve
spacectl stack task --id eks-dev          -- tofu destroy -auto-approve
spacectl stack task --id network-dev      -- tofu destroy -auto-approve
```

Or directly with OpenTofu (requires local state):

```bash
cd stacks/prometheus  && tofu destroy
cd stacks/argo-cd     && tofu destroy
cd stacks/eks-addons  && tofu destroy
cd stacks/eks         && tofu destroy
cd stacks/network     && tofu destroy
```

> **Note:** EKS cluster deletion takes ~10 minutes. KMS keys have a 7-day deletion window after `tofu destroy` — this is by design and cannot be shortened.

---

## EKS Creation Fails Mid-Apply

**Symptom:** `eks-dev` stack fails after 15+ minutes with a control plane error.

**Cause:** Usually one of:

1. IAM role propagation delay — EKS rejects the cluster role within the first ~15 seconds of creation
2. Subnet tag missing — VPC-CNI cannot discover the correct subnets
3. KMS key policy not yet propagated

**Response:**

1. Do **not** re-trigger immediately — the cluster may be in a partial state
2. Check AWS Console → EKS → Clusters for the cluster status and error message
3. If status is `FAILED`, run `tofu destroy` on the eks stack to clean it up
4. Resolve the root cause, then re-apply

**IAM propagation** is the most common cause. A re-apply usually succeeds on the second attempt without any code changes.

---

## Spacelift Management Stack

### Management stack runs with `+0 ~0 -0` delta and creates nothing

**Symptom:** The management stack shows `FINISHED` but no app stacks, IAM role, or policies are created. Delta is `+0 ~0 -0` on every run.

**Cause:** The management stack's **project root** is not set to `stacks/spacelift`. OpenTofu is running against an empty or wrong directory.

**Fix:** In the Spacelift UI, go to the management stack → **Settings** → verify **Project root** is exactly `stacks/spacelift`. Update if wrong, then trigger a new run.

---

### `No value for required variable: spacelift_api_url / spacelift_api_key_id / spacelift_api_key_secret`

**Symptom:** Plan fails with `No value for required variable` for `spacelift_api_url`, `spacelift_api_key_id`, or `spacelift_api_key_secret`.

**Cause:** These variables were removed from `variables.tf` when the provider was simplified to auto-configure from environment variables. They were passed as `-var` flags but are no longer declared.

**Fix:** Use environment variables instead of `-var` flags when running locally:

```sh
export SPACELIFT_API_KEY_ENDPOINT=https://<org>.app.spacelift.io
export SPACELIFT_API_KEY_ID=<key-id>
export SPACELIFT_API_KEY_SECRET=<key-secret>

tofu apply -var="repository=argocd-eks-terraform"
```

---

### `provider not configured` for `spacelift-io/spacelift`

**Symptom:** `Error: provider not configured — either the API key must be set or the following settings must be provided: api_key_endpoint, api_key_id, api_key_secret`

**Cause:** The Spacelift provider environment variables were not exported in the current shell session before running `tofu apply`.

**Fix:** Verify the variables are set, then re-run in the same terminal session:

```sh
echo $SPACELIFT_API_KEY_ENDPOINT
echo $SPACELIFT_API_KEY_ID
echo $SPACELIFT_API_KEY_SECRET

# If any are empty, re-export and re-apply
export SPACELIFT_API_KEY_ENDPOINT=https://<org>.app.spacelift.io
export SPACELIFT_API_KEY_ID=<key-id>
export SPACELIFT_API_KEY_SECRET=<key-secret>

tofu apply -var="repository=argocd-eks-terraform"
```

Note: `tofu init` succeeds without these variables — only `plan` and `apply` require them.

---

### `unauthorized: you need 'Stack manage' or 'Stack create' permission`

**Symptom:** Apply fails on `spacelift_stack` and `spacelift_policy` resources with `unauthorized: you need 'Stack manage' or 'Stack create' permission or Space admin role`.

**Cause A:** The management stack does not have the **Administrative** flag enabled. Without it, the stack can only manage its own resources, not create other stacks or policies.

**Fix A:** In the Spacelift UI → management stack → **Settings** → enable **Administrative**. Trigger a new run.

**Cause B:** The API key used for a local apply has read-only permissions.

**Fix B:** Create a new API key with the **Admin** role in Spacelift UI → **Settings → API keys**. Use it for the bootstrap apply, then delete it afterwards.

---

### `could not attach the aws integration: unauthorized: you need to configure trust relationship`

**Symptom:** Apply fails on all `spacelift_aws_integration_attachment` resources with `unauthorized: you need to configure trust relationship section in your AWS account`.

Spacelift validates the trust policy contents at attachment time — it inspects the policy, not just attempts `AssumeRole`. Both the Principal account ID and the ExternalId condition must match exactly what Spacelift expects for your organization.

---

**Cause A:** IAM propagation — the role was just created and hasn't propagated globally yet.

**Fix A:** The `time_sleep.iam_propagation` resource (30s delay) handles this for new runs. If it fails on the first run, trigger a re-run — the role will be visible by then.

---

**Cause B:** Wrong Spacelift AWS account ID or ExternalId pattern in the trust policy.

Spacelift does not use a universal AWS account — the account ID varies by organization. The `spacelift_aws_integration` provider resource does **not** reliably export these values. The authoritative source is the Spacelift UI.

**Diagnosis — get the exact trust policy Spacelift expects:**

In the Spacelift UI → **Integrations** → click the integration → look for a **Trust relationship** section. It shows the exact policy including the account ID and ExternalId pattern. For this org it looks like:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "577638371743" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringLike": { "sts:ExternalId": "fearfactor3@*" }
    }
  }]
}
```

Key points:

- **Principal** is the Spacelift infrastructure account (`577638371743` for this org — not `324880187172`)
- **Condition operator** is `StringLike`, not `StringEquals`
- **ExternalId** is an org-scoped wildcard pattern (`<org-name>@*`), not a UUID

**Diagnosis — check what the live role actually has:**

```sh
aws iam get-role --role-name spacelift-integration \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
```

Compare the Principal account ID and Condition to the expected values above.

**Fix B:** The correct values are in `var.spacelift_account_id` (default `577638371743`) and `var.spacelift_org_name` (default `fearfactor3`) in [stacks/spacelift/variables.tf](../../stacks/spacelift/variables.tf). If those variables are correct, triggering a new run will update the role in-place.

To unblock immediately without waiting for a Spacelift run, patch the role directly:

```sh
aws iam update-assume-role-policy \
  --role-name spacelift-integration \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::577638371743:root" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringLike": { "sts:ExternalId": "fearfactor3@*" }
      }
    }]
  }'
```

Then trigger a new run.

---

**Cause C:** The role was tainted and recreated, but `time_sleep.iam_propagation` did not re-run because it was already in state.

**Fix C:** Taint the sleep resource so the 30s delay runs again on the next apply:

```sh
spacectl stack task --id argocd-eks-terraform -- \
  tofu state rm time_sleep.iam_propagation
```

Then trigger a new run — `time_sleep` will be recreated (triggering the 30s delay) before the attachments are attempted.

---

### `spacectl stack task` returns `unauthorized`

**Symptom:** `spacectl stack task` returns `unauthorized: You're logged in. Maybe you don't have access to the resource?`

**Cause:** The spacectl API key has read-only permissions and cannot execute tasks on stacks.

**Fix:** Upgrade the API key to Admin in Spacelift UI → **Settings → API keys** → select the key → change role to **Admin**. If the key cannot be edited, create a new Admin key and re-authenticate:

```sh
spacectl profile login --endpoint https://<org>.app.spacelift.io
```

---

### App stacks fail with `No valid credential sources found` for AWS

**Symptom:** An app stack (`network-dev`, `eks-dev`, etc.) fails with `No valid credential sources found` for the AWS provider.

**Cause:** The `spacelift-integration` IAM role and its attachments have not been created yet. App stacks receive AWS credentials via `spacelift_aws_integration_attachment` — they have no credentials until the management stack has successfully applied.

**Fix:** Ensure the management stack has finished successfully (all resources including integration attachments created). Then trigger the app stack again, starting from `network-dev` to follow the dependency chain.

---

### `job assignment failed: the following inputs are missing`

**Symptom:** A dependent stack (e.g. `eks-addons-dev`) fails with `job assignment failed: the following inputs are missing: eks-addons-dev.eks_cluster_endpoint => TF_VAR_eks_cluster_endpoint`.

**Cause:** The upstream stack (`eks-dev`) has never been successfully applied, so it has no outputs to pass to dependent stacks.

**Fix:** Follow the dependency chain in order. Trigger `network-dev` manually — Spacelift will propagate runs down the chain automatically:

```text
network-dev → eks-dev → eks-addons-dev → argo-cd-dev + prometheus-dev
```

Do not trigger downstream stacks until their upstream dependency shows `FINISHED`.

---

### Spacelift output values have extra quotes (e.g. `"10.0.0.0/16"`)

**Symptom:** A stack fails with a CIDR or string validation error where the value shown has embedded double-quotes — e.g. `"\"10.0.0.0/16\""` is not a valid CIDR block.

**Cause:** Spacelift JSON-encodes string output values. When `spacectl stack outputs --output json` returns a value it is stored as a JSON string within JSON — `"\"10.0.0.0/16\""`. A naive `jq -r .value` strips one layer of quoting but leaves the inner quotes, resulting in `"10.0.0.0/16"` (with literal double-quotes) being passed as the variable value.

**Fix (already applied):** The `_tofu-plan-stack.yml` CI workflow strips surrounding quotes from all Spacelift output values using bash parameter expansion before writing to `GITHUB_ENV`. If you see this in a new context, strip the leading/trailing `"` from the value before use:

```bash
val="${val#\"}"; val="${val%\"}"
```

---

### Downstream stacks receive `null` for cross-stack outputs

**Symptom:** A plan fails with `Call to function "base64decode" failed` or a provider config error referencing a variable that shows as `null` in the CI log.

**Cause:** Spacelift returns `null` for outputs not yet available (e.g. `cluster_ca_certificate` before `eks-dev` has applied). The CI stub injection sets a valid placeholder, but the Spacelift fetch step was overwriting it with the string `"null"`.

**Fix (already applied):** The jq expression in `_tofu-plan-stack.yml` includes `select(.value != null)` to skip null outputs entirely, preserving the stub values. If you encounter this elsewhere, guard against null before writing to the environment.

---

### Module file changes do not trigger Spacelift stack runs

**Symptom:** You push a change to `modules/eks/` or `modules/network/` but the corresponding `eks-dev` / `network-dev` stack does not queue a new tracked run.

**Cause:** Spacelift only scans a stack's `project_root` for file changes. The `stacks/eks` project root is `stacks/eks/` — changes inside `modules/eks/` fall outside that path and are invisible to Spacelift's change detection.

**Fix (already applied):** The `eks` and `network` stacks have `additional_project_globs` configured to also watch their respective module directories:

```hcl
additional_project_globs = ["modules/eks/**/*"]    # for eks stacks
additional_project_globs = ["modules/network/**/*"] # for network stacks
```

If you add a new stack that references a local module, add the module path to `extra_globs` in `env_stack_types` in `stacks/spacelift/main.tf`.

---

### Retrying a failed run does not trigger downstream stacks

**Symptom:** `eks-dev` fails, you fix the issue and retry the run. It succeeds, but `eks-addons-dev` never queues.

**Cause:** This is a documented Spacelift limitation — retries of previously failed runs do not trigger dependent stacks even when successful. See [Spacelift docs: stack dependency reference limitations](https://docs.spacelift.io/concepts/stack/stack-dependencies.html#stack-dependency-reference-limitations).

**Fix:** After a retry succeeds, manually trigger the next stack in the dependency chain:

```text
network-dev → eks-dev → eks-addons-dev → argo-cd-dev + prometheus-dev
```

To trigger `eks-addons-dev` from the CLI:

```bash
spacectl stack trigger --id eks-addons-dev
```

---

### Helm release stuck in failed state — `cannot re-use a name that is still in use`

**Symptom:** A Spacelift apply fails with `Error: installation failed — cannot re-use a name that is still in use` on a `helm_release` resource.

**Cause:** A previous failed apply installed a partial Helm release, leaving it in `failed` or `pending-install` state. Helm blocks reinstalling a release that is already registered, even in a failed state.

**Fix:** Uninstall the stuck release directly from the cluster, then re-trigger the Spacelift apply:

```bash
# Authenticate first
aws eks update-kubeconfig --name <cluster-name> --region us-east-1

helm uninstall <release-name> -n <namespace>
# e.g. helm uninstall aws-load-balancer-controller -n kube-system
#      helm uninstall external-secrets -n external-secrets
#      helm uninstall cluster-autoscaler -n kube-system
```

**Prevention (already applied):** All Helm releases in `eks-addons` now have `cleanup_on_fail = true`, which automatically rolls back and removes resources if a release fails, preventing stuck state on future failures.
