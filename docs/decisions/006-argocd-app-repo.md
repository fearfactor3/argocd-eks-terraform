# ADR-006: ArgoCD Application Repository Strategy

**Status**: Open — decision pending

---

## Context

ArgoCD is deployed into each environment as a GitOps engine, but it is not currently configured to watch any Git repository. No `Application` or `ApplicationSet` CRD is deployed. ArgoCD is installed but not functional as a GitOps engine until a source repository is defined.

Two structural approaches exist for managing the manifests ArgoCD will reconcile:

| Approach | Description |
|----------|-------------|
| **Monorepo** | Application manifests live in this repository, under a new top-level directory (e.g. `apps/`) |
| **Separate app repo** | Application manifests live in a dedicated repository (e.g. `argocd-apps`), watched by ArgoCD in each environment |

---

## Options Considered

### Option A: Monorepo

Add an `apps/` directory to this repository. ArgoCD's `Application` resources (or an `ApplicationSet`) point at paths within `argocd-eks-terraform`.

**Pros:**

- Single repository for infrastructure and application state — one PR covers both
- Spacelift already manages this repo; no second repo to bootstrap
- Simpler to get started

**Cons:**

- Infrastructure changes and application changes are coupled in the same branch protection and CI pipeline
- PR blast radius grows: a broken app manifest can block an infra merge
- As the number of applications grows, the repo becomes harder to navigate
- Does not scale well if multiple teams own different applications

### Option B: Separate App Repository

Create a dedicated repository (e.g. `argocd-apps`) that contains only Kubernetes manifests, Helm values, and Kustomize overlays. This repo is watched by ArgoCD in each environment.

**Pros:**

- Clear separation of concerns — infra engineers and application teams work in different repos
- Application deploys do not require infra repo access
- Standard GitOps pattern; well-supported by ArgoCD's `ApplicationSet` with `git` generator
- App repo can have its own, lighter-weight CI (manifest linting, Kubeconform validation)

**Cons:**

- Two repositories to maintain and bootstrap
- Cross-cutting changes (e.g. new namespace + new application) require coordinated PRs across both repos
- Slightly more complex initial setup

---

## Decision

**Not yet made.** The following factors should guide the choice:

- **Single operator / personal project**: Option A (monorepo) is simpler and sufficient.
- **Team with separate infra and app owners**: Option B (separate repo) enforces the right access boundary.
- **If staging environment is added**: Option B scales better — the `ApplicationSet` git generator can target different overlays per environment from a single source.

---

## Action Required

Before the first production deployment, decide on Option A or B and:

1. Create the Application/ApplicationSet manifest (or repo)
2. Add an `argocd_application` or `argocd_application_set` Helm value to `stacks/argo-cd/main.tf` pointing at the chosen source
3. Update this ADR to `Accepted` with the chosen approach

Until this decision is made, ArgoCD is deployed but serves no GitOps function.
