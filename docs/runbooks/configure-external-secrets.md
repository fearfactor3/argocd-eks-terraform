# Runbook: Configure External Secrets Operator

Set up a `ClusterSecretStore` and create your first `ExternalSecret` so application workloads can consume secrets from AWS Secrets Manager or SSM Parameter Store without storing values in Git.

---

## Overview

| | |
| - | - |
| **Scope** | Cluster-wide (one `ClusterSecretStore` per backend per cluster) |
| **Risk** | Low — ESO only reads from the secret store; it never writes back |
| **Prerequisite** | ESO is deployed (`kubectl get pods -n external-secrets`) and the cluster has been applied |

ESO is deployed via `stacks/eks-addons`. The ESO service account (`external-secrets/external-secrets`) uses IRSA to assume an IAM role scoped to secrets under `/<cluster-name>/` in both AWS Secrets Manager and SSM Parameter Store. No credentials are stored in the cluster.

---

## Step 1 — Create a ClusterSecretStore

A `ClusterSecretStore` is the cluster-scoped connection to a secret backend. Create one per backend (Secrets Manager, SSM). The ESO IRSA role handles authentication — no access keys required.

### AWS Secrets Manager

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1        # match your cluster's region
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

### SSM Parameter Store

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-ssm
spec:
  provider:
    aws:
      service: ParameterStore
      region: us-east-1        # match your cluster's region
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

Verify the store is ready:

```bash
kubectl get clustersecretstore
# Expect: READY=True
```

---

## Step 2 — Store a Secret in AWS

The ESO IRSA policy permits reads under `/<cluster-name>/`. Follow this naming convention so the policy matches without modification.

### Store in Secrets Manager

```bash
# Example: database credentials for the nginx app in dev
aws secretsmanager create-secret \
  --name "argocd-dev/nginx/db-credentials" \
  --secret-string '{"username":"app","password":"s3cr3t"}'
```

### Store in SSM Parameter Store

```bash
# Example: API key as a SecureString parameter
aws ssm put-parameter \
  --name "/argocd-dev/nginx/api-key" \
  --type SecureString \
  --value "my-api-key"
```

---

## Step 3 — Create an ExternalSecret

An `ExternalSecret` lives in the application's namespace and references the `ClusterSecretStore`. ESO materialises it as a standard Kubernetes `Secret` on the configured refresh interval.

### From AWS Secrets Manager (JSON secret)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: nginx-dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials      # name of the Kubernetes Secret to create
    creationPolicy: Owner
  data:
    - secretKey: username     # key in the Kubernetes Secret
      remoteRef:
        key: argocd-dev/nginx/db-credentials
        property: username    # field in the JSON secret
    - secretKey: password
      remoteRef:
        key: argocd-dev/nginx/db-credentials
        property: password
```

### From SSM Parameter Store

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-key
  namespace: nginx-dev
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-ssm
    kind: ClusterSecretStore
  target:
    name: api-key
    creationPolicy: Owner
  data:
    - secretKey: value
      remoteRef:
        key: /argocd-dev/nginx/api-key
```

Apply and verify:

```bash
kubectl apply -f externalsecret.yaml

# Check sync status
kubectl get externalsecret db-credentials -n nginx-dev
# Expect: READY=True, STATUS=SecretSynced

# Confirm the Secret was created
kubectl get secret db-credentials -n nginx-dev
```

---

## Step 4 — Reference the Secret in a Pod

The materialised Kubernetes `Secret` is consumed like any other secret:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

Or as a volume:

```yaml
volumes:
  - name: db-creds
    secret:
      secretName: db-credentials
```

---

## Naming Convention

| Environment | Secrets Manager path | SSM path |
| ----------- | -------------------- | -------- |
| dev | `argocd-dev/<app>/<secret-name>` | `/argocd-dev/<app>/<param-name>` |
| prod | `argocd-prod/<app>/<secret-name>` | `/argocd-prod/<app>/<param-name>` |

The IRSA policy matches `arn:aws:secretsmanager:*:*:secret:<cluster-name>/*` and `arn:aws:ssm:*:*:parameter/<cluster-name>/*`. Secrets outside this prefix will be denied.

---

## Troubleshooting

### `ClusterSecretStore` shows `InvalidProviderConfig`

```bash
kubectl describe clustersecretstore aws-secrets-manager
```

Common causes: wrong region, or the ESO pods are not yet running. Check:

```bash
kubectl get pods -n external-secrets
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### `ExternalSecret` shows `SecretSyncedError`

```bash
kubectl describe externalsecret <name> -n <namespace>
```

Common causes:

- Secret path does not exist in Secrets Manager / SSM — verify with `aws secretsmanager get-secret-value --secret-id <path>`
- Path does not match the IRSA policy prefix — check the secret name starts with `<cluster-name>/`
- IAM role not yet propagated — wait 30 seconds and check again

### Secret not updating after rotation

ESO syncs on the `refreshInterval` (default `1h`). Force an immediate sync by deleting and recreating the `ExternalSecret`, or by annotating it:

```bash
kubectl annotate externalsecret <name> -n <namespace> \
  force-sync=$(date +%s) --overwrite
```
