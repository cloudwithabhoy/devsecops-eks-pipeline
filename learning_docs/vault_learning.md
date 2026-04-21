# HashiCorp Vault — Secrets Management

---

## What is Vault?

Vault is a **secrets management tool** by HashiCorp.

Its job: **store secrets (passwords, API keys, tokens, certificates) securely and inject them into applications at runtime — without the secrets ever touching Git, environment variables, or Kubernetes manifests.**

---

## The problem Vault solves

Without Vault, secrets end up in bad places:

**In Git (worst):**
```yaml
env:
  - name: DB_PASSWORD
    value: "mysecretpassword123"   # anyone with repo access sees this
```

**In Kubernetes Secrets (better, but still not great):**
```yaml
apiVersion: v1
kind: Secret
data:
  password: bXlzZWNyZXRwYXNzd29yZDEyMw==  # just base64 — not encrypted
```
Kubernetes Secrets are base64 encoded, not encrypted. Anyone with kubectl access can decode them instantly.

**With Vault (correct):**
- Secrets stored encrypted in Vault's storage backend
- App gets a short-lived token to fetch the secret at startup
- Secret never written to disk, never in Git, never in an env var
- Every access is logged — full audit trail

---

## Where Vault fits in this pipeline

```
ArgoCD deploys Juice Shop pod
        ↓
Vault Agent sidecar starts alongside the app container
        ↓
Vault Agent authenticates to Vault using the pod's Kubernetes identity
        ↓
Vault Agent fetches the secret and writes it to a file inside the pod
        ↓
Juice Shop reads the secret from the file
        ↓
Secret never stored in Git, K8s manifest, or env var ← YOU ARE HERE
```

---

## Core Concepts

### Secret Engine

A **Secret Engine** is a plugin inside Vault that knows how to store and generate a specific type of secret.

| Engine | What it does |
|---|---|
| `kv` (Key-Value) | Store static secrets (username, password, API key) |
| `aws` | Generate temporary AWS credentials on demand |
| `database` | Generate temporary DB credentials on demand |
| `pki` | Generate TLS certificates |

We use `kv-v2` — the standard key-value engine for storing static secrets.

---

### Auth Method

How Vault verifies **who is asking** for a secret.

| Method | Used by |
|---|---|
| `kubernetes` | Pods on EKS — authenticate using their ServiceAccount token |
| `token` | Direct token-based access (for admins) |
| `aws` | AWS IAM roles |
| `userpass` | Username + password (for humans) |

We use the **Kubernetes auth method** — pods prove their identity using the ServiceAccount token Kubernetes automatically mounts into every pod.

---

### Policy

A Vault **Policy** defines what a authenticated identity is allowed to do.

```hcl
path "secret/data/juice-shop/*" {
  capabilities = ["read"]
}
```

This says: the holder of this policy can only **read** secrets under `secret/data/juice-shop/`. They cannot write, delete, or access any other path.

Least privilege — each app only gets access to its own secrets.

---

### Vault Agent

The **Vault Agent** is a sidecar container that runs alongside your app container inside the same pod.

It:
1. Authenticates to Vault using the pod's Kubernetes ServiceAccount token
2. Fetches the secret from Vault
3. Writes the secret to a shared in-memory volume (not disk)
4. Keeps the secret refreshed (re-fetches before it expires)

Your app reads the secret from a file — it never talks to Vault directly.

```
Pod
├── juice-shop container  ← reads secret from /vault/secrets/config
└── vault-agent sidecar  ← fetches secret from Vault, writes to shared volume
```

---

### Kubernetes Auth Flow

```
Pod starts
    ↓
Vault Agent reads the ServiceAccount token Kubernetes mounted into the pod
    ↓
Vault Agent sends token to Vault: "I am pod X in namespace juice-shop"
    ↓
Vault checks: is there a role for pods in namespace juice-shop?
    ↓
YES → Vault issues a Vault token with the attached policy
    ↓
Vault Agent uses the token to fetch secrets
    ↓
Writes secrets to /vault/secrets/ inside the pod
    ↓
Juice Shop reads from /vault/secrets/
```

---

## Files we create

### vault/vault-policy.hcl

Defines what Juice Shop is allowed to read from Vault.

```hcl
path "secret/data/juice-shop/*" {
  capabilities = ["read"]
}
```

---

### vault/vault-auth.yaml

Configures the Kubernetes auth method — tells Vault how to validate pod identity.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: juice-shop
  namespace: juice-shop
```

---

## vault-policy.hcl — Line by Line

```hcl
path "secret/data/juice-shop/*" {
  capabilities = ["read"]
}
```

---

```hcl
path "secret/data/juice-shop/*"
```
- `path` — the Vault secret path this policy applies to.
- `secret/data/` — the standard prefix when using the `kv-v2` secret engine. When you store a secret at `secret/juice-shop/db`, Vault internally stores it at `secret/data/juice-shop/db`.
- `juice-shop/` — a folder namespace — all Juice Shop secrets live here, separated from other apps.
- `*` — wildcard — this policy applies to all secrets under `juice-shop/`. So `juice-shop/db`, `juice-shop/api-key`, `juice-shop/smtp` — all covered by one policy.

```hcl
capabilities = ["read"]
```
- What the policy holder is allowed to do at this path.

| Capability | What it allows |
|---|---|
| `read` | Fetch a secret |
| `list` | List secret names (not values) |
| `create` | Create new secrets |
| `update` | Modify existing secrets |
| `delete` | Delete secrets |

We only give `read` — Juice Shop needs to fetch secrets, not manage them. Least privilege.

---

## vault-auth.yaml — Line by Line

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: juice-shop
  namespace: juice-shop
```

---

```yaml
apiVersion: v1
kind: ServiceAccount
```
- `ServiceAccount` is a standard Kubernetes resource — it gives a pod a Kubernetes identity.
- Every pod in Kubernetes runs under a ServiceAccount. By default it's the `default` ServiceAccount, which has no special permissions.
- We create a dedicated `juice-shop` ServiceAccount so Vault can identify Juice Shop pods specifically.

```yaml
metadata:
  name: juice-shop
  namespace: juice-shop
```
- `name: juice-shop` — the name of the ServiceAccount. Vault's Kubernetes auth role will reference this name.
- `namespace: juice-shop` — must be in the same namespace as the Juice Shop pods.

**How Vault uses this:**
When Vault Agent authenticates, it sends the ServiceAccount token + the ServiceAccount name + namespace to Vault. Vault checks if a role exists for that ServiceAccount in that namespace — if yes, issues a token with the attached policy.

---

## How Vault Agent injects secrets (annotation-based)

To enable Vault Agent injection, you add annotations to the Deployment in `helm/juice-shop/templates/deployment.yaml`:

```yaml
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "juice-shop"
        vault.hashicorp.com/agent-inject-secret-config: "secret/data/juice-shop/config"
```

- `agent-inject: "true"` — tells the Vault webhook to inject a Vault Agent sidecar into this pod
- `role: "juice-shop"` — the Vault Kubernetes auth role to use for authentication
- `agent-inject-secret-config` — the secret path to fetch. The secret will be written to `/vault/secrets/config` inside the pod

Juice Shop then reads from `/vault/secrets/config` instead of environment variables.

---

## AWS session steps

```bash
# Install Vault via Helm
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=true"

# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=90s

# Enable Kubernetes auth method
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Configure Kubernetes auth
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

# Enable KV secrets engine
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

# Create a test secret for Juice Shop
kubectl exec -n vault vault-0 -- vault kv put secret/juice-shop/config \
  db_password="supersecret" \
  api_key="abc123"

# Apply the policy
kubectl cp vault/policies/vault-policy.hcl vault/vault-0:/tmp/vault-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write juice-shop /tmp/vault-policy.hcl

# Create Kubernetes auth role
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/juice-shop \
  bound_service_account_names=juice-shop \
  bound_service_account_namespaces=juice-shop \
  policies=juice-shop \
  ttl=1h

# Apply ServiceAccount
kubectl apply -f vault/vault-auth.yaml
```

---

## Vault vs Kubernetes Secrets

| | Kubernetes Secrets | Vault |
|---|---|---|
| Encryption | Base64 only (not encrypted) | AES-256 encrypted at rest |
| Access control | Kubernetes RBAC | Fine-grained policies per path |
| Audit log | No | Every read/write logged |
| Secret rotation | Manual | Automatic (dynamic secrets) |
| Who can read | Anyone with kubectl access | Only roles with the right policy |
| In Git | Easy to accidentally commit | Never touches Git |

---

## How this fits in our DevSecOps pipeline

```
Phase 8  — ECR push     (image stored with SHA tag)
Phase 10 — Helm         (chart defines what runs)
Phase 9  — ArgoCD       (deploys the chart to EKS)
Phase 11 — Kyverno      (validates every pod before it runs)
Phase 13 — Vault        (injects secrets into pods at runtime) ← YOU ARE HERE
Phase 14 — Prometheus   (monitors the running system)
```
