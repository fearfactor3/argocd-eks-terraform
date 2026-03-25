# Emergency: Destroying Production Infrastructure

> **This procedure bypasses the production plan policy that protects critical
> infrastructure from accidental destruction. Use it only when there is no other
> option — for example, a full environment decommission or a complete rebuild after
> unrecoverable state corruption.**
>
> The override is scoped to a single run. It is not a persistent setting and does
> not need to be reverted after use.

---

## When This Is Appropriate

- Full environment decommission (environment is being permanently retired)
- Complete rebuild after state is irrecoverably corrupted
- Account migration requiring infrastructure to be rebuilt from scratch

## When This Is NOT Appropriate

- Routine resource replacement (fix the Terraform configuration instead)
- Cost reduction (resize or reconfigure, do not destroy and recreate)
- Debugging (use `tofu plan` locally to understand the change first)

---

## Checklist

Before triggering any production destruction run:

- [ ] Confirm there is no active traffic or workload depending on the infrastructure
- [ ] Verify you have a recent state backup (`spacectl stack state download --id <stack>`)
- [ ] Notify any stakeholders that the environment is going down
- [ ] Confirm destroy order (see below) — stacks must be destroyed in reverse dependency order
- [ ] Arrange a second approver if operating in a team — emergency destruction runs require 2 approvals

---

## Procedure

Destroy in reverse dependency order. Run each command and wait for the run to complete
and be approved before proceeding to the next stack.

**1. argo-cd-prod and prometheus-prod** (can be triggered in parallel):

```sh
spacectl stack run trigger --id argo-cd-prod \
  --metadata '{"allow_destruction": "true"}' \
  --type DESTROY

spacectl stack run trigger --id prometheus-prod \
  --metadata '{"allow_destruction": "true"}' \
  --type DESTROY
```

**2. eks-addons-prod** (after both above complete):

```sh
spacectl stack run trigger --id eks-addons-prod \
  --metadata '{"allow_destruction": "true"}' \
  --type DESTROY
```

**3. eks-prod** (after eks-addons-prod completes):

```sh
spacectl stack run trigger --id eks-prod \
  --metadata '{"allow_destruction": "true"}' \
  --type DESTROY
```

**4. network-prod** (after eks-prod completes):

```sh
spacectl stack run trigger --id network-prod \
  --metadata '{"allow_destruction": "true"}' \
  --type DESTROY
```

Each run will surface a warning in the Spacelift UI and run log:

```text
EMERGENCY OVERRIDE ACTIVE: protected resource destruction permitted for this run only
```

This warning is intentional — it makes the override visible in the audit trail.

---

## After the Procedure

- Confirm all stacks show empty state in the Spacelift UI
- If the environment is being permanently retired, delete the Spacelift stacks via
  the `spacelift` management stack (remove the environment from `var.environments`
  and apply)
- Document what was destroyed and why in the incident or change record
