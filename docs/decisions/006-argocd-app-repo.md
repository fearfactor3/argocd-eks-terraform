# ADR-006: ArgoCD Application Repository Strategy

**Status**: Accepted — Option B (separate app repository). Each application lives in its own Git repository. ArgoCD watches the app repo and syncs Kubernetes manifests to the cluster. See [connect-app-repo.md](../runbooks/connect-app-repo.md) for the connection procedure.

---

## Context

ArgoCD is deployed into each environment as a GitOps engine, but it is not currently configured to watch any Git repository. No `Application` or `ApplicationSet` CRD is deployed. ArgoCD is installed but not functional as a GitOps engine until a source repository is defined.

Two structural approaches exist for managing the manifests ArgoCD will reconcile:

| Approach              | Description                                                                                                        |
| --------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **Monorepo**          | Application manifests live in this repository, under a new top-level directory (e.g. `apps/`)                     |
| **Separate app repo** | Application manifests live in a dedicated repository (e.g. `argocd-apps`), watched by ArgoCD in each environment  |

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

**Option B (separate app repository).**

Each application lives in its own Git repository with Kubernetes manifests (plain YAML, Kustomize, or Helm). ArgoCD watches the app repo directly. This keeps infrastructure and application concerns cleanly separated and scales better as the number of applications grows.

The `var.argocd_source_repo` variable in the `argo-cd` stack controls which repository the platform AppProject permits. Set this to your app repo URL in `dev.tfvars` / `prod.tfvars` when connecting a new app.

**Reference implementation:** [fearfactor3/nginx-kustomize-example](https://github.com/fearfactor3/nginx-kustomize-example) is used as the worked example in the runbook — it demonstrates the recommended Kustomize base + per-environment overlay structure.

---

## Action Required

Follow [docs/runbooks/connect-app-repo.md](../runbooks/connect-app-repo.md) to connect an application repository to ArgoCD.
