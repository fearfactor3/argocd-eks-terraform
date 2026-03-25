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

**Cause A:** The `aws_iam_role.spacelift_integration` and `spacelift_aws_integration_attachment` resources were created in parallel. Spacelift validates the trust relationship at attachment time, before AWS IAM has propagated the new role globally (IAM is eventually consistent).

**Fix A:** The `time_sleep.iam_propagation` resource (30s delay) handles this for new runs. If it fails on the first run, trigger a re-run — subsequent runs skip the sleep (role already exists) but the trust relationship is now visible.

**Cause B:** The IAM role's trust policy was created with an empty `ExternalId`. This can happen if the role was tainted and recreated from a cached state before `spacelift_aws_integration.this.external_id` was populated, or if running against stale code.

**Diagnosis:**

```sh
aws iam get-role --role-name spacelift-integration \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
# Look for "sts:ExternalId": "" — empty string confirms this cause
# Or check that the Principal uses the correct aws_account_id (not a hardcoded value)
```

**Fix B:** The trust policy must include both the correct Spacelift AWS account ID and the ExternalId that Spacelift validates during attachment. The current code derives both from `spacelift_aws_integration.this` (which is created before the IAM role, so `external_id` and `aws_account_id` are always populated).

If the role is in a bad state, patch it directly using the values from the live integration:

```sh
# Get the correct values from the Spacelift integration resource
EXTERNAL_ID=$(tofu -chdir=stacks/spacelift output -raw spacelift_external_id 2>/dev/null)
AWS_ACCOUNT_ID=$(tofu -chdir=stacks/spacelift output -raw spacelift_aws_account_id 2>/dev/null)

# Or read them from the Spacelift provider state via spacectl / Spacelift UI
# Then patch the role:
aws iam update-assume-role-policy \
  --role-name spacelift-integration \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": { \"AWS\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:root\" },
      \"Action\": \"sts:AssumeRole\",
      \"Condition\": {
        \"StringEquals\": { \"sts:ExternalId\": \"${EXTERNAL_ID}\" }
      }
    }]
  }"
```

Then trigger a new run.

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
