# Runbook: EKS Cluster Access

How to grant and manage `kubectl` access to the EKS clusters in this project.

---

## Background

By default, only the IAM entity that created the EKS cluster (the `spacelift-integration` role) has cluster access. Your personal IAM credentials do not have access until explicitly granted via `admin_iam_principals`.

This project uses `authentication_mode = "API_AND_CONFIG_MAP"`, which enables both:

- **EKS Access Entry API** — the modern approach, managed as Terraform resources in `modules/eks/main.tf`
- **aws-auth ConfigMap** — the legacy approach, used by managed node groups (cannot be removed until all node groups have access entries)

> **Migration path:** Once all node groups are registered as access entries, switch `authentication_mode` to `"API"` only and remove the ConfigMap dependency. This removes a secondary authentication path and reduces attack surface.

---

## Granting Temporary kubectl Access

The preferred approach for ad-hoc operator access is to inject the variable temporarily via the Spacelift UI without committing anything to code.

### Step 1 — Add the environment variable in Spacelift

In the Spacelift UI → `eks-dev` → **Environment** → **+ Add variable**:

| Name                          | Value                                              | Secret |
| ----------------------------- | -------------------------------------------------- | ------ |
| `TF_VAR_admin_iam_principals` | `["arn:aws:iam::{account-id}:user/{your-user}"]`   | No     |

### Step 2 — Trigger a tracked run

Trigger a new run on the `eks-dev` stack. Spacelift applies the access entry.

### Step 3 — Update kubeconfig and connect

```bash
aws eks update-kubeconfig --name argocd-dev --region us-east-1
kubectl get nodes
```

### Step 4 — Revoke when done

Remove `TF_VAR_admin_iam_principals` from the Spacelift environment and trigger another run. OpenTofu deletes the access entry and policy association.

---

## Granting Permanent Access

If a principal needs permanent access (e.g. a shared ops role), add it to `stacks/eks/dev.tfvars`:

```hcl
admin_iam_principals = [
  "arn:aws:iam::{account-id}:role/{ops-role}",
]
```

Prefer role ARNs over user ARNs — access is revoked by removing the role rather than editing this list.

---

## Security Considerations

| Concern                  | Guidance                                                                                                                           |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Temporary access**     | Use the Spacelift UI approach above. Remove the variable and re-apply when done.                                                   |
| **Permanent access**     | Use role ARNs in tfvars. Audit `admin_iam_principals` quarterly and remove stale principals.                                       |
| **Audit trail**          | All access entry changes are logged by CloudTrail under `eks:CreateAccessEntry` and `eks:DeleteAccessEntry`. Ensure it is enabled. |
| **Least privilege**      | `AmazonEKSClusterAdminPolicy` is full cluster admin. For read-only access, use `AmazonEKSViewPolicy` in `modules/eks/main.tf`.     |
| **Privilege escalation** | Permanent additions to `admin_iam_principals` grant full cluster admin and should go through code review.                          |

---

## Troubleshooting

### `error: You must be logged in to the server (Unauthorized)`

Your IAM identity is not in `admin_iam_principals`. Follow the temporary access steps above. Confirm your identity matches the ARN you added:

```bash
aws sts get-caller-identity
```

### `kubernetes cluster unreachable: the server has asked for the client to provide credentials`

Your AWS credentials are expired or kubeconfig is stale. Refresh credentials, then:

```bash
aws eks update-kubeconfig --name argocd-dev --region us-east-1
```

### `AccessDenied` when assuming the Spacelift role

The `spacelift-integration` trust policy is scoped to the Spacelift AWS account only — personal IAM credentials cannot assume it. Use the Spacelift UI approach instead.
