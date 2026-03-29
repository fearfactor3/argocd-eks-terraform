# Runbook: Initial Bootstrap

First-time deployment of all stacks from zero AWS resources to a fully running dev environment, followed by prod promotion.

---

## Overview

| | |
| - | - |
| **Scope** | dev environment first; prod after dev is stable for 24 hours |
| **Risk** | Medium — greenfield deploy, no existing state to preserve |
| **Rollback time** | ~45 min (`tofu destroy` in reverse dependency order) |
| **EKS creation time** | 15–20 min — not instant-rollback once started |

**Dependency order:**

```text
Spacelift management stack (manual, UI)
  └─► iam (Spacelift triggers)
  └─► network-dev → eks-dev → eks-addons-dev → argo-cd-dev + prometheus-dev
  └─► network-prod → eks-prod → eks-addons-prod → argo-cd-prod + prometheus-prod  (after dev stable)
```

---

## Prerequisites

Complete all of the following before starting. Do not proceed if any item is unresolved.

- [ ] AWS credentials active with AdministratorAccess (for the one-time management stack bootstrap)
- [ ] Spacelift account provisioned and accessible
- [ ] `tofu` installed locally (`tofu version` — expect `~> 1.10`)
- [ ] `spacectl` installed and authenticated: `spacectl whoami`
- [ ] `opa` installed (for policy checks): `opa version`
- [ ] GitHub secrets configured: `SPACELIFT_API_KEY_ID`, `SPACELIFT_API_KEY_SECRET`
- [ ] GitHub variables configured: `AWS_REGION`, `SPACELIFT_API_URL`
- [ ] All CI checks green on the target branch before merging to `main`

> `AWS_ROLE_ARN` is set after the `iam` stack applies — not a pre-req.

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

## Phase 1 — Spacelift Management Stack Bootstrap

The Spacelift management stack manages all other stacks as code. It must be created manually once, then it provisions everything else.

### 1a — Create the management stack in the Spacelift UI

**New stack** with these settings:

| Field | Value |
| --- | --- |
| Repository | `argocd-eks-terraform` |
| Project root | `stacks/spacelift` |
| Branch | `main` |
| Tool | OpenTofu |
| Administrative | **enabled** |
| Autodeploy | **enabled** |

### 1b — Run the first apply locally

Running locally avoids IAM propagation race conditions that occur when the apply runs inside Spacelift for the first time. Your local AWS credentials must have `AdministratorAccess`.

```sh
export SPACELIFT_API_KEY_ENDPOINT=https://<org>.app.spacelift.io
export SPACELIFT_API_KEY_ID=<key-id>
export SPACELIFT_API_KEY_SECRET=<key-secret>

cd stacks/spacelift
tofu init
tofu apply -var="repository=argocd-eks-terraform"
```

Expect `+N` delta — stacks, environment variables, dependencies, policies, IAM role, and AWS integration attachments are all created in one apply.

On success:

- All app stacks exist in Spacelift: `iam`, `network-dev/prod`, `eks-dev/prod`, `eks-addons-dev/prod`, `argo-cd-dev/prod`, `prometheus-dev/prod`
- The `spacelift-integration` IAM role exists in AWS (assumed by all Spacelift runs)
- Stack dependencies, cross-stack output references, and plan/approval policies are in place

### 1c — Upload state to Spacelift

Upload the local state file so subsequent Spacelift runs are consistent with what was applied:

```sh
spacectl stack state upload -id argocd-eks-terraform < terraform.tfstate
rm terraform.tfstate terraform.tfstate.backup
```

**Validation:**

In the Spacelift UI, confirm all stacks are created and show `NONE` state (never run).

---

## Phase 2 — IAM Stack

The `iam` stack creates the GitHub Actions OIDC provider and read-only plan role used by CI. Trigger it from the Spacelift UI.

**Validation:**

```bash
aws iam get-role --role-name github-actions-plan
# Expect: role with AssumeRolePolicyDocument referencing token.actions.githubusercontent.com
```

Store the role ARN as a GitHub secret. The ARN is in the `iam` stack's **Outputs** tab in Spacelift:

```bash
gh secret set AWS_ROLE_ARN --body "<role-arn-from-iam-stack-outputs>"
```

---

## Phase 3 — Merge to Main → Dev Deploy

1. Merge the feature branch to `main` after all CI checks pass.
2. Spacelift detects the merge and queues runs automatically.

**Expected run sequence:**

| Stack | Depends on | Expected duration |
| ----- | --------- | ---------------- |
| `network-dev` | — | ~3 min |
| `eks-dev` | `network-dev` finished | ~15–20 min |
| `eks-addons-dev` | `eks-dev` finished | ~3 min |
| `argo-cd-dev` | `eks-addons-dev` finished | ~5 min |
| `prometheus-dev` | `eks-addons-dev` finished | ~5 min |

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
# Expect: 1 node (dev), STATUS=Ready, EXTERNAL-IP=<none>

# Verify ALB controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
# Expect: 1 pod Running

# Verify ArgoCD pods
kubectl get pods -n argocd
# Expect: all pods Running

# Verify ArgoCD ALB Ingress provisioned
kubectl get ingress -n argocd
# Expect: ADDRESS populated (ALB DNS hostname)

# Verify Prometheus stack
kubectl get pods -n prometheus
# Expect: prometheus, grafana, loki, alloy pods Running

# Verify EBS CSI
kubectl get pods -n kube-system | grep ebs-csi
# Expect: ebs-csi-controller Running

# Verify Alloy is shipping flow logs to Loki
# Open Grafana → Explore → Loki datasource → query {exporter="OTLP"}
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
5. Approve `eks-addons-prod` after `eks-prod` finishes (~3 min).
6. Approve `argo-cd-prod` and `prometheus-prod` after `eks-addons-prod` finishes.

**Validation:** Repeat the Phase 4 checks against the prod cluster name.

---

## Verification Signals

| Timeframe | Signal | Where to check |
| --------- | ------ | ------------- |
| 0–3 min | `network-dev` stack `Finished` | Spacelift UI |
| 3–25 min | `eks-dev` stack `Finished`, nodes `Ready` | Spacelift UI + `kubectl get nodes` |
| 25–28 min | `eks-addons-dev` stack `Finished`, ALB controller pod `Running` | Spacelift UI + `kubectl get pods -n kube-system` |
| 28–33 min | ArgoCD UI reachable via ALB Ingress hostname | Browser |
| 33–38 min | Grafana UI reachable, Prometheus targets up | Browser |
| 35–45 min | Loki receiving VPC flow log data from Alloy | Grafana → Explore |

---

## Troubleshooting

If a stack fails during any phase, see [bootstrap-troubleshooting.md](bootstrap-troubleshooting.md) for common failure patterns, rollback procedure, and EKS creation contingencies.

---

## Post-Deployment Checklist

### Immediate (within 1 hour)

- [ ] Retrieve and rotate the ArgoCD admin password
- [ ] Confirm Grafana datasources are working (Prometheus and Loki)
- [ ] Confirm Alloy is delivering flow logs to Loki
- [ ] Add AWS Budget alert for dev environment (prevents surprise bills)

### Short-term (within 1 week)

- [x] Resolve ADR-006 — connect ArgoCD to an application repository (see [connect-app-repo.md](connect-app-repo.md))
- [ ] Resolve ADR-009 — add TLS to ArgoCD and Grafana endpoints before sharing URLs externally
- [ ] Deploy Cluster Autoscaler (ADR-007) to reduce idle node costs

### Before Production Go-Live

- [x] ADR-006 resolved and ArgoCD watching a real app repo (see [connect-app-repo.md](connect-app-repo.md))
- [ ] ADR-008 resolved — secrets management strategy in place
- [ ] ADR-009 resolved — TLS on all external endpoints (certificate_arn variable wired; pending domain + ACM cert)
- [x] NetworkPolicy resources deployed between namespaces (argocd, prometheus, kube-system)
- [ ] Staging environment added to `var.environments` and validated
