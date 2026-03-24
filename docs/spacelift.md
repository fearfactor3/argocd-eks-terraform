# Spacelift

Spacelift manages state, triggers runs on merge to `main`, and injects cross-stack
outputs as `TF_VAR_*` environment variables into dependent stacks.

---

## Policies

Two plan policies and one approval policy gate all Spacelift runs:

| Policy | Environment | Type | Effect |
| --- | --- | --- | --- |
| `dev-plan` | dev | PLAN | Warns on destructions and large blast radius — no hard blocks |
| `prod-plan` | prod | PLAN | Hard-blocks destruction of protected resources; warns on others |
| `prod-approval` | prod | APPROVAL | Requires 1 approval for any apply; 2 for emergency destructions |

Policy sources are in `stacks/spacelift/policies/` and managed as code via the `spacelift` stack.

### Testing Policies Locally

Policies have OPA unit tests. Run them with:

```sh
make test-policies
```

Or individually:

```sh
opa test stacks/spacelift/policies/dev-plan.rego stacks/spacelift/policies/dev-plan_test.rego -v
opa test stacks/spacelift/policies/prod-plan.rego stacks/spacelift/policies/prod-plan_test.rego -v
opa test stacks/spacelift/policies/prod-approval.rego stacks/spacelift/policies/prod-approval_test.rego -v
```

Tests also run automatically in CI on every pull request (`Test Rego policies` job in `opentofu-validate`).

---

## Production Approval Workflow

Every tracked run on a prod stack (`network-prod`, `eks-prod`, `argo-cd-prod`,
`prometheus-prod`) stops at the approval gate before applying, regardless of what
changed. Autodeploy is disabled on all prod stacks by design.

To approve a run:

1. Open the run in the Spacelift UI
2. Review the plan output and confirm the changes are expected
3. Click **Approve** — the run proceeds to apply

To reject a run:

1. Open the run in the Spacelift UI
2. Click **Reject** — the run is cancelled and no changes are applied

Emergency destruction runs require **2 approvals** before proceeding (see
[Emergency: Destroying Production Infrastructure](runbooks/emergency-destroy.md)).
In a single-operator setup, lower the threshold in
`stacks/spacelift/policies/prod-approval.rego` from `>= 2` to `>= 1`.

---

## Create an API Key

1. In the Spacelift UI, go to **Settings → API keys → Create API key**
2. Give it a name (e.g. `github-actions`) and assign the **Read** role (plan workflows only need read access)
3. Copy the key ID and secret — the secret is shown once only
4. Store them as GitHub secrets (see [Bootstrap: Step 2](bootstrap.md#step-2-configure-github-secrets-and-variables))

## Authenticate spacectl

```sh
spacectl profile login --endpoint https://<org>.app.spacelift.io
```

## List Stack Outputs

```sh
spacectl stack outputs --id network-dev --output json
spacectl stack outputs --id eks-dev --output json
```

## Trigger a Manual Run

```sh
spacectl stack run trigger --id eks-dev
```

## Download Stack State

```sh
spacectl stack state download --id network-prod
spacectl stack state download --id eks-prod
```
