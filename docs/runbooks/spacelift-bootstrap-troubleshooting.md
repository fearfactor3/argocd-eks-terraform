# Runbook: Spacelift Bootstrap Troubleshooting

Common failures encountered when bootstrapping the Spacelift management stack for the first time and how to resolve them.

---

## Management stack runs with `+0 ~0 -0` delta and creates nothing

**Symptom:** The management stack shows `FINISHED` but no app stacks, IAM role, or policies are created. Delta is `+0 ~0 -0` on every run.

**Cause:** The management stack's **project root** is not set to `stacks/spacelift`. OpenTofu is running against an empty or wrong directory.

**Fix:** In the Spacelift UI, go to the management stack → **Settings** → verify **Project root** is exactly `stacks/spacelift`. Update if wrong, then trigger a new run.

---

## `No value for required variable: spacelift_api_url / spacelift_api_key_id / spacelift_api_key_secret`

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

## `provider not configured` for `spacelift-io/spacelift`

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

## `unauthorized: you need 'Stack manage' or 'Stack create' permission`

**Symptom:** Apply fails on `spacelift_stack` and `spacelift_policy` resources with `unauthorized: you need 'Stack manage' or 'Stack create' permission or Space admin role`.

**Cause A:** The management stack does not have the **Administrative** flag enabled. Without it, the stack can only manage its own resources, not create other stacks or policies.

**Fix A:** In the Spacelift UI → management stack → **Settings** → enable **Administrative**. Trigger a new run.

**Cause B:** The API key used for a local apply has read-only permissions.

**Fix B:** Create a new API key with the **Admin** role in Spacelift UI → **Settings → API keys**. Use it for the bootstrap apply, then delete it afterwards.

---

## `could not attach the aws integration: unauthorized: you need to configure trust relationship`

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

## `spacectl stack task` returns `unauthorized`

**Symptom:** `spacectl stack task` returns `unauthorized: You're logged in. Maybe you don't have access to the resource?`

**Cause:** The spacectl API key has read-only permissions and cannot execute tasks on stacks.

**Fix:** Upgrade the API key to Admin in Spacelift UI → **Settings → API keys** → select the key → change role to **Admin**. If the key cannot be edited, create a new Admin key and re-authenticate:

```sh
spacectl profile login --endpoint https://<org>.app.spacelift.io
```

---

## App stacks fail with `No valid credential sources found` for AWS

**Symptom:** An app stack (`network-dev`, `eks-dev`, etc.) fails with `No valid credential sources found` for the AWS provider.

**Cause:** The `spacelift-integration` IAM role and its attachments have not been created yet. App stacks receive AWS credentials via `spacelift_aws_integration_attachment` — they have no credentials until the management stack has successfully applied.

**Fix:** Ensure the management stack has finished successfully (all resources including integration attachments created). Then trigger the app stack again, starting from `network-dev` to follow the dependency chain.

---

## `job assignment failed: the following inputs are missing`

**Symptom:** A dependent stack (e.g. `eks-addons-dev`) fails with `job assignment failed: the following inputs are missing: eks-addons-dev.eks_cluster_endpoint => TF_VAR_eks_cluster_endpoint`.

**Cause:** The upstream stack (`eks-dev`) has never been successfully applied, so it has no outputs to pass to dependent stacks.

**Fix:** Follow the dependency chain in order. Trigger `network-dev` manually — Spacelift will propagate runs down the chain automatically:

```text
network-dev → eks-dev → eks-addons-dev → argo-cd-dev + prometheus-dev
```

Do not trigger downstream stacks until their upstream dependency shows `FINISHED`.
