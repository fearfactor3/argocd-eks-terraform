# ADR-001: Spacelift over Atlantis / Terraform Cloud

**Status**: Accepted

---

## Context

Managing OpenTofu across multiple stacks with cross-stack dependencies requires a CI/CD system that can:

1. Enforce a specific apply order (network → eks → argo-cd/prometheus)
2. Pass outputs from one stack as inputs to another without manual copy-paste
3. Gate production changes behind approval workflows
4. Apply policy as code to plan output before any apply runs

The main candidates considered were:

| Tool | Model |
|---|---|
| **Atlantis** | Self-hosted, GitHub webhook-driven, one workspace per repo directory |
| **Terraform Cloud / HCP Terraform** | SaaS, workspace-per-directory, native cross-workspace output sharing via data sources |
| **Spacelift** | SaaS, stack-per-directory, first-class stack dependencies and policy engine |

---

## Decision

Use **Spacelift**.

---

## Reasons

### Stack dependencies are first-class

Spacelift has `spacelift_stack_dependency` and `spacelift_stack_dependency_reference` resources that model the dependency graph explicitly and automatically pass outputs between stacks. Atlantis has no dependency concept — you would need to manually trigger stacks in order or write custom scripts. Terraform Cloud supports cross-workspace data sources but they require the consuming workspace to be re-planned whenever the upstream output changes.

### Policy as code with OPA

Spacelift has a built-in OPA-based policy engine. PLAN policies run against `terraform show -json` output before apply is allowed. APPROVAL policies gate runs on human sign-off. Both are version-controlled Rego files in this repository — they are reviewed in pull requests alongside the infrastructure they protect.

Atlantis has no policy engine. Terraform Cloud has Sentinel (policy-as-code), but Sentinel uses a proprietary language. OPA/Rego is open source and transferable knowledge.

### Per-environment autodeploy control

Spacelift's `autodeploy` flag lets dev stacks apply automatically on merge while requiring explicit approval for prod. In Atlantis, autodeploy is global or requires custom workflow configuration. In Terraform Cloud, this requires separate workspace settings per environment.

### The meta-stack pattern

Spacelift stacks are themselves OpenTofu-managed resources (via the Spacelift provider). The `stacks/spacelift/` directory is a meta-stack that creates and manages all app stacks as code. This means stack configuration is version-controlled, reviewed, and applied through the same PR workflow as application code. Atlantis does not support this pattern. Terraform Cloud workspaces can be managed via the TFE provider but require a separate management layer.

---

## Trade-offs

- **Cost**: Spacelift is not free. For a small team or personal project, Terraform Cloud's free tier or self-hosted Atlantis may be more economical.
- **Vendor lock-in**: Spacelift-specific resources (`spacelift_stack`, `spacelift_policy`, etc.) are not portable. Migrating away would require recreating the dependency graph and policy logic in another tool.
- **Operational complexity**: Running Atlantis yourself means owning uptime and upgrades. Spacelift is SaaS, which shifts that burden to the vendor.
