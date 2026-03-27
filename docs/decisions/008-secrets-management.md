# ADR-008: Secrets Management for Application Workloads

**Status**: Accepted — Option A (External Secrets Operator)

---

## Context

The infrastructure layer has strong secrets hygiene: KMS encrypts Kubernetes Secrets at rest, IRSA provides pod-scoped AWS credentials, and no long-lived credentials are stored in the cluster. However, there is currently no mechanism for application workloads (deployed via ArgoCD) to securely receive secrets such as database passwords, API keys, or third-party credentials.

Storing secrets in Git — even encrypted — and syncing them through ArgoCD requires a solution that integrates with the GitOps workflow.

The three most common approaches for Kubernetes secrets management in a GitOps context are:

| Tool | Model |
|------|-------|
| **External Secrets Operator (ESO)** | Pulls secrets from an external store (AWS Secrets Manager, SSM Parameter Store) and materialises them as Kubernetes `Secret` objects. Syncs on a configurable interval. |
| **Sealed Secrets** | Encrypts secrets into `SealedSecret` CRDs that can be committed to Git. The in-cluster controller decrypts them with a private key. |
| **HashiCorp Vault** | Centralised secrets engine. Integrates with Kubernetes via the Vault Agent Injector or the Vault Secrets Operator. |

---

## Options Considered

### Option A: External Secrets Operator (ESO)

ESO watches `ExternalSecret` CRDs and fetches the referenced values from AWS Secrets Manager or SSM Parameter Store, writing them as standard Kubernetes `Secret` objects.

**Pros:**

- Native AWS integration — secrets already managed in Secrets Manager are immediately available
- Works well with IRSA: ESO's service account assumes an IAM role scoped to specific secret ARNs
- `ExternalSecret` manifests (which reference secret names, not values) are safe to commit to Git
- Low operational overhead — no separate secrets server to manage

**Cons:**

- Requires secrets to exist in AWS Secrets Manager before workloads can start (bootstrapping order matters)
- Kubernetes `Secret` objects are created in-cluster — still need KMS encryption at rest (already configured)
- Polling interval means secret rotations take up to N minutes to propagate

### Option B: Sealed Secrets

The `kubeseal` CLI encrypts a `Secret` manifest with the cluster's public key, producing a `SealedSecret` that can be committed to Git. The in-cluster controller decrypts it.

**Pros:**

- Fully GitOps-native — secrets travel through the same PR process as everything else
- No external dependency at runtime (no AWS API call needed to start a pod)
- Simple mental model

**Cons:**

- The cluster's sealing key must be backed up; losing it means re-sealing all secrets
- Re-sealing is required when rotating the cluster key or migrating clusters
- No centralised audit trail of who accessed which secret (unlike Secrets Manager)
- Does not integrate with existing AWS Secrets Manager secrets

### Option C: HashiCorp Vault

Vault provides a full secrets engine with dynamic credentials, audit logging, and fine-grained access policies.

**Pros:**

- Most capable option — dynamic credentials, PKI, database secrets engine
- Strong audit trail
- Multi-cluster and multi-cloud capable

**Cons:**

- Highest operational complexity — Vault itself must be deployed, configured, and made highly available
- Requires its own backup and disaster recovery procedures
- Significant over-engineering for a two-environment EKS setup

---

## Decision

**Option A — External Secrets Operator** is deployed in `stacks/eks-addons` via Helm. An IRSA role scoped to the `external-secrets:external-secrets` service account grants read access to AWS Secrets Manager and SSM Parameter Store paths under `/<cluster-name>/`. Application teams create `ExternalSecret` CRs referencing secrets by path — no secret values are stored in Git.

See [docs/runbooks/configure-external-secrets.md](../runbooks/configure-external-secrets.md) for how to configure a `ClusterSecretStore` and create your first `ExternalSecret`.
