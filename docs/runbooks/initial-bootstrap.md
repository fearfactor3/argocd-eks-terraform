# Runbook: Initial Bootstrap

First-time deployment of all stacks from zero AWS resources to a fully running dev environment, followed by prod promotion.

---

## Overview

| | |
|-|-|
| **Scope** | dev environment first; prod after dev is stable for 24 hours |
| **Risk** | Medium — greenfield deploy, no existing state to preserve |
| **Rollback time** | ~45 min (`tofu destroy` in reverse dependency order) |
| **EKS creation time** | 15–20 min — not instant-rollback once started |

**Dependency order:**

```
IAM (manual, once per AWS account)
  └─► Spacelift bootstrap (manual, UI)
        └─► network-dev → eks-dev → argo-cd-dev + prometheus-dev
        └─► network-prod → eks-prod → argo-cd-prod + prometheus-prod  (after dev stable)
```

---

## Prerequisites

Complete all of the following before starting. Do not proceed if any item is unresolved.

- [ ] AWS credentials active with sufficient permissions (AdministratorAccess for bootstrap)
- [ ] Spacelift account provisioned and accessible
- [ ] `tofu` installed locally (`tofu version` — expect `~> 1.10`)
- [ ] `spacectl` installed and authenticated: `spacectl whoami`
- [ ] `opa` installed (for policy checks): `opa version`
- [ ] GitHub secrets configured: `AWS_ROLE_ARN`, `SPACELIFT_API_KEY_ID`, `SPACELIFT_API_KEY_SECRET`
- [ ] GitHub variables configured: `AWS_REGION`, `SPACELIFT_API_URL`
- [ ] All CI checks green on the target branch before merging to `main`

---

## Preflight Checks

Run these commands and confirm all exit 0 before proceeding.

```bash
# Verify AWS identity
aws sts get-caller-identity

# Verify Spacelift connectivity
spacectl whoami

# Verify policy tests pass
make check-policies

# Verify module unit tests pass
make test-modules

# Verify formatting and lint
make lint
```

**Go / No-Go**: If any command fails, stop and resolve the issue before continuing.

---

## Phase 1 — IAM Stack (once per AWS account)

The IAM stack creates the GitHub Actions OIDC provider and a read-only plan role. It is applied manually and lives outside Spacelift.

```bash
cd stacks/iam
tofu init
tofu plan \
  -var="github_org=<your-github-user-or-org>" \
  -var="github_repo=argocd-eks-terraform"
```

Review the plan. Expect: ~3 resources (OIDC provider, IAM role, policy attachment).

```bash
tofu apply \
  -var="github_org=<your-github-user-or-org>" \
  -var="github_repo=argocd-eks-terraform"

# Store the role ARN as a GitHub secret
gh secret set AWS_ROLE_ARN --body "$(tofu output -raw github_actions_plan_role_arn)"
```

**Validation:**
```bash
aws iam get-role --role-name github-actions-plan
# Expect: role returned with AssumeRolePolicyDocument referencing token.actions.githubusercontent.com
```

---

## Phase 2 — Spacelift Bootstrap (manual, UI)

The Spacelift management stack must be created manually once in the Spacelift UI. It then manages all other stacks as code.

1. In the Spacelift UI: **New stack**
   - Repository: `argocd-eks-terraform`
   - Project root: `stacks/spacelift`
   - Branch: `main`
   - Tool: OpenTofu
   - Autodeploy: **enabled**

2. Trigger an apply from the Spacelift UI.

   This creates all app stacks: `iam`, `network-dev`, `network-prod`, `eks-dev`, `eks-prod`, `argo-cd-dev`, `argo-cd-prod`, `prometheus-dev`, `prometheus-prod` and wires their dependencies.

**Validation:**

In the Spacelift UI, confirm all stacks are created and show `Inactive` (ready to run, not yet applied).

---

## Phase 3 — Merge to Main → Dev Deploy

1. Merge the feature branch to `main` after all CI checks pass.
2. Spacelift detects the merge and queues runs automatically.

**Expected run sequence:**

| Stack | Depends on | Expected duration |
|-------|-----------|------------------|
| `network-dev` | — | ~3 min |
| `eks-dev` | `network-dev` finished | ~15–20 min |
| `argo-cd-dev` | `eks-dev` finished | ~5 min |
| `prometheus-dev` | `eks-dev` finished | ~5 min |

Monitor progress in the Spacelift UI. Each stack should reach `Finished` state.

> **Note:** Dev stacks have `autodeploy = true` and apply without approval.
> Prod stacks have `autodeploy = false` — they will queue but wait for manual approval.

---

## Phase 4 — Verify Dev

```bash
# Get kubeconfig
aws eks update-kubeconfig \
  --name <cluster-name>-dev \
  --region us-east-1

# Verify nodes are Ready and in private subnets
kubectl get nodes -o wide
# Expect: 2 nodes, STATUS=Ready, EXTERNAL-IP=<none>

# Verify ArgoCD pods
kubectl get pods -n argocd
# Expect: all pods Running

# Verify ArgoCD NLB assigned
kubectl get svc -n argocd argocd-server
# Expect: EXTERNAL-IP populated (NLB hostname)

# Verify Prometheus stack
kubectl get pods -n prometheus
# Expect: prometheus, grafana, loki, alloy pods Running

# Verify EBS CSI
kubectl get pods -n kube-system | grep ebs-csi
# Expect: ebs-csi-controller Running

# Verify Alloy is shipping flow logs to Loki
# Open Grafana → Explore → Loki datasource → query {job="loki.source.cloudwatch"}
# Expect: flow log entries appearing within ~2 minutes
```

---

## Phase 5 — Prod Deploy

**Only proceed after dev has been stable for at least 24 hours.**

Prod stacks do not autodeploy. Each requires a manual approval in the Spacelift UI before applying.

1. In the Spacelift UI, trigger `network-prod` manually (or wait for it to queue on the next push).
2. Review the plan output carefully. Click **Approve**.
3. After `network-prod` finishes, `eks-prod` will queue automatically.
4. Approve `eks-prod` after reviewing the plan (~20 min to apply).
5. Approve `argo-cd-prod` and `prometheus-prod` after `eks-prod` finishes.

**Validation:** Repeat the Phase 4 checks against the prod cluster name.

---

## Verification Signals

| Timeframe | Signal | Where to check |
|-----------|--------|---------------|
| 0–3 min | `network-dev` stack `Finished` | Spacelift UI |
| 3–25 min | `eks-dev` stack `Finished`, nodes `Ready` | Spacelift UI + `kubectl get nodes` |
| 25–30 min | ArgoCD UI reachable on NLB hostname | Browser |
| 30–35 min | Grafana UI reachable, Prometheus targets up | Browser |
| 35–45 min | Loki receiving VPC flow log data from Alloy | Grafana → Explore |

---

## Rollback Procedure

### When to rollback

- Any stack stuck in `Failed` for more than 10 minutes with no progress
- `kubectl get nodes` shows `NotReady` after 25 minutes
- ArgoCD or Prometheus pods not reaching `Running` after 10 minutes

### How to rollback

Destroy in reverse dependency order:

```bash
# Via Spacelift (preferred)
spacectl stack run trigger --id prometheus-dev
spacectl stack run trigger --id argo-cd-dev
spacectl stack run trigger --id eks-dev
spacectl stack run trigger --id network-dev
```

Or directly with OpenTofu:

```bash
cd stacks/prometheus && tofu destroy
cd stacks/argo-cd    && tofu destroy
cd stacks/eks        && tofu destroy
cd stacks/network    && tofu destroy
```

> **Note:** EKS cluster deletion takes ~10 minutes. KMS keys have a 7-day deletion window after `tofu destroy` — this is by design and cannot be shortened.

---

## Contingency: EKS Creation Fails Mid-Apply

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

## Post-Deployment Checklist

### Immediate (within 1 hour)

- [ ] Retrieve and rotate the ArgoCD admin password
- [ ] Confirm Grafana datasources are working (Prometheus and Loki)
- [ ] Confirm Alloy is delivering flow logs to Loki
- [ ] Add AWS Budget alert for dev environment (prevents surprise bills)
- [ ] Tag NLBs with `Project` and `ManagedBy` tags (currently missing from load balancer resources)

### Short-term (within 1 week)

- [ ] Resolve ADR-006 — connect ArgoCD to an application repository
- [ ] Resolve ADR-009 — add TLS to ArgoCD and Grafana endpoints before sharing URLs externally
- [ ] Deploy Cluster Autoscaler (ADR-007) to reduce idle node costs
- [ ] Evaluate ALB Ingress Controller to consolidate NLBs (ADR-005)

### Before Production Go-Live

- [ ] ADR-006 resolved and ArgoCD watching a real app repo
- [ ] ADR-008 resolved — secrets management strategy in place
- [ ] ADR-009 resolved — TLS on all external endpoints
- [ ] NetworkPolicy resources deployed between namespaces (argocd, prometheus, kube-system)
- [ ] Staging environment added to `var.environments` and validated
