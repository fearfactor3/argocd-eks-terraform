# Runbook: Connect an Application Repository to ArgoCD

Connect a Git repository containing Kubernetes manifests to ArgoCD so it begins reconciling the cluster state automatically.

---

## Overview

| | |
| - | - |
| **Scope** | Single application repository, one environment at a time |
| **Risk** | Low — ArgoCD syncs are non-destructive by default until `prune: true` is set |
| **Prerequisite** | ArgoCD is deployed and the UI is reachable (see [initial-bootstrap.md](initial-bootstrap.md)) |

ArgoCD is deployed with a `platform` AppProject that restricts which repositories it will sync from. The `argocd_source_repo` Terraform variable controls this allowlist. Connecting a new app repo is a two-step process:

1. Update `argocd_source_repo` in the stack tfvars to permit the repo
2. Create an `Application` or `ApplicationSet` in ArgoCD pointing at the repo

---

## Reference Implementation

[fearfactor3/nginx-kustomize-example](https://github.com/fearfactor3/nginx-kustomize-example) is used as the worked example throughout this runbook. It follows the recommended Kustomize base + per-environment overlay structure:

```text
nginx-kustomize-example/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml       # nginx:latest, 2 replicas
│   └── service.yaml          # ClusterIP on port 80
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml    # namespace: nginx-dev
    │   └── deployment.yaml   # patch: 1 replica, modest resources
    └── prod/
        ├── kustomization.yaml
        ├── namespace.yaml    # namespace: nginx-prod
        └── deployment.yaml   # patch: 3 replicas, production resources
```

This structure is the recommended starting point for new app repositories:

- **Base** defines the common configuration shared across environments
- **Overlays** patch the base per environment (replica count, resource limits, namespace)
- Each overlay creates its own namespace so environments are fully isolated

---

## Step 1 — Permit the Repository in the AppProject

Set `argocd_source_repo` in the environment's tfvars file to the HTTPS URL of the app repository:

```hcl
# stacks/argo-cd/dev.tfvars
argocd_source_repo = "https://github.com/fearfactor3/nginx-kustomize-example"
```

```hcl
# stacks/argo-cd/prod.tfvars
argocd_source_repo = "https://github.com/fearfactor3/nginx-kustomize-example"
```

Trigger an `argo-cd` stack run in Spacelift (or `tofu apply` locally). The `platform` AppProject will update its `sourceRepos` to allow only the specified repo. ArgoCD will reject any `Application` pointing at a different source.

> **Note:** `argocd_source_repo` accepts a single URL. If you need to allow multiple repositories, change the variable type to `list(string)` and update the `sourceRepos` reference in `main.tf` accordingly.

---

## Step 2 — Create an Application in ArgoCD

With the repo permitted, create an ArgoCD `Application` that points at the correct overlay for the target environment.

### Option A: ArgoCD UI

1. Open the ArgoCD UI (see the ALB Ingress hostname from `kubectl get ingress -n argocd`)
2. Click **New App**
3. Fill in the fields:

| Field | Dev value | Prod value |
| ----- | --------- | ---------- |
| Application name | `nginx-example` | `nginx-example` |
| Project | `platform` | `platform` |
| Sync policy | Automatic | Automatic |
| Repository URL | `https://github.com/fearfactor3/nginx-kustomize-example` | same |
| Revision | `HEAD` | `HEAD` |
| Path | `overlays/dev` | `overlays/prod` |
| Cluster URL | `https://kubernetes.default.svc` | same |
| Namespace | `nginx-dev` | `nginx-prod` |

1. Enable **Prune resources** and **Self heal**
1. Click **Create**

### Option B: kubectl

Apply the `Application` manifest directly:

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-example
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/fearfactor3/nginx-kustomize-example
    targetRevision: HEAD
    path: overlays/dev          # change to overlays/prod for prod cluster
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-dev        # change to nginx-prod for prod cluster
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

---

## Step 3 — Verify Sync

```bash
# Check Application status
kubectl get application nginx-example -n argocd

# Expect: SYNC STATUS=Synced, HEALTH STATUS=Healthy

# Verify pods are running in the app namespace
kubectl get pods -n nginx-dev
# Expect: nginx-deployment pod(s) Running

# Verify the service exists
kubectl get svc -n nginx-dev
```

In the ArgoCD UI, the application card should show green (Synced + Healthy) within ~30 seconds of creation.

---

## Troubleshooting

### `ComparisonError: repository not permitted`

The repo URL is not in `sourceRepos` for the `platform` AppProject. Verify that `argocd_source_repo` in the tfvars matches the `repoURL` in the Application exactly (including `https://` vs `git@`), then re-apply the `argo-cd` stack.

### `OutOfSync` immediately after creation

ArgoCD detected drift between the repo and cluster state. Click **Sync** in the UI (or wait for the automated sync). If prune is enabled and resources were manually deleted, they will be re-created.

### Pods not starting after sync

```bash
kubectl describe pod -n nginx-dev -l app=nginx
kubectl get events -n nginx-dev --sort-by='.lastTimestamp'
```

Common causes: image pull errors (`nginx:latest` is public so auth is not required), resource quota exceeded, or PSS policy violations (nginx runs as root — the `nginx-dev` namespace is not subject to restricted PSS enforcement).
