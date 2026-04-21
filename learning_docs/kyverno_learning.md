# Kyverno — Kubernetes Policy Engine

---

## What is Kyverno?

Kyverno is a **policy engine for Kubernetes**.

Its job: **intercept every resource before it's created in the cluster and check it against your rules.**

If a resource violates a policy — Kyverno blocks it. The pod never starts.
If a resource passes — Kyverno lets it through.

The name comes from the Greek word for "govern" — that's exactly what it does.

---

## The problem Kyverno solves

Kubernetes will run whatever you tell it to. By default there's nothing stopping:
- A container running as root (full system access inside the pod)
- A pod with no CPU/memory limits (can starve other pods)
- An image tagged as `latest` (you don't know what's actually running)
- A pod with no security context at all

Kyverno enforces rules that block these before they ever reach the cluster.

---

## Where Kyverno fits in this pipeline

```
Code pushed to GitHub
        ↓
CI: build → scan → push image to ECR
        ↓
CI: update image tag in helm/values.yaml
        ↓
ArgoCD: detects Git change → runs helm upgrade
        ↓
Kyverno: intercepts every resource ArgoCD tries to create  ← YOU ARE HERE
        ↓
PASS → resource created in cluster
FAIL → blocked, ArgoCD sync fails, nothing broken gets in
```

Kyverno sits **between ArgoCD and the cluster**. ArgoCD says "create this pod" — Kyverno checks the pod spec before Kubernetes accepts it.

---

## How Kyverno works

Kyverno runs as a **webhook** inside the cluster.

When any resource is created or updated:
1. Kubernetes sends it to Kyverno first (before saving it)
2. Kyverno checks it against all matching policies
3. If all policies pass → Kubernetes creates the resource
4. If any policy fails → Kubernetes rejects it with an error message

This is called an **Admission Controller** — it controls what's admitted into the cluster.

```
kubectl apply / helm upgrade / ArgoCD sync
        ↓
Kubernetes API Server
        ↓
Kyverno Admission Webhook  ← checks here
        ↓
PASS: etcd (cluster state stored)
FAIL: rejected with error
```

---

## Policy types

Kyverno has three types of policies:

| Type | What it does |
|---|---|
| **Validate** | Check a resource — block it if it doesn't meet the rule |
| **Mutate** | Automatically modify a resource before it's created (e.g. add a label) |
| **Generate** | Automatically create new resources when another resource is created |

In this project we use **Validate** — we only want to check and block, not modify.

---

## validationFailureAction

Every Kyverno policy has this field. It controls what happens when a resource fails the policy:

| Value | What happens |
|---|---|
| `Enforce` | Resource is **blocked** — hard gate, nothing gets in |
| `Audit` | Resource is **allowed but logged** — observation mode, for testing |

We use `Enforce` — this is a security pipeline, we want hard gates.

---

## ClusterPolicy vs Policy

| Kind | Scope |
|---|---|
| `ClusterPolicy` | Applies to all namespaces in the cluster |
| `Policy` | Applies only to the namespace it's created in |

We use `ClusterPolicy` — our rules should apply everywhere, not just `juice-shop`.

---

## Our three policies

### Policy 1 — disallow-root.yaml
Block any container that runs as root.
Root inside a container = root on the node if the container escapes. This is one of the most common container breakout paths.

### Policy 2 — require-resource-limits.yaml
Block any pod that doesn't set CPU and memory limits.
Without limits, one bad pod can consume all node resources and crash everything else.

### Policy 3 — disallow-latest-tag.yaml
Block any image using the `latest` tag.
`latest` is mutable — you never know what's actually running. Our pipeline uses immutable SHA tags for exactly this reason. Kyverno enforces this at the cluster level.

---

## disallow-root.yaml — Line by Line

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-root-user
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-runAsNonRoot
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Containers must not run as root. Set securityContext.runAsNonRoot: true"
        pattern:
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
```

---

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
```
- `apiVersion: kyverno.io/v1` — Kyverno registers its own custom resource types. `ClusterPolicy` is one of them, living in the `kyverno.io` API group.
- `kind: ClusterPolicy` — applies to every namespace in the cluster, not just one.

```yaml
metadata:
  name: disallow-root-user
```
- The name of this policy. Shows up in Kyverno reports and error messages when a resource is blocked.

```yaml
spec:
  validationFailureAction: Enforce
```
- `Enforce` — hard block. Any pod that violates this policy is rejected. ArgoCD sync fails, the bad config never reaches the cluster.

```yaml
  rules:
    - name: check-runAsNonRoot
```
- A policy can have multiple rules. Each rule is a separate check.
- `name` — identifies this rule in logs and error messages.

```yaml
      match:
        resources:
          kinds:
            - Pod
```
- `match` — which resources this rule applies to.
- `kinds: Pod` — only check Pod resources. Deployments create Pods — when ArgoCD applies the Deployment, Kubernetes creates Pods, and Kyverno checks each Pod.

```yaml
      validate:
        message: "Containers must not run as root. Set securityContext.runAsNonRoot: true"
```
- `validate` — this is a validation rule (check and block, don't modify).
- `message` — the error message shown when a pod is blocked. Should tell the developer exactly what to fix.

```yaml
        pattern:
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
```
- `pattern` — the shape a Pod must match to be allowed. Think of it as a template — the pod's spec must contain these fields with these values.
- `securityContext.runAsNonRoot: true` — the pod must have this field set to `true`. If it's missing or `false`, the pod is blocked.

---

## require-resource-limits.yaml — Line by Line

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-resource-limits
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "CPU and memory limits are required on all containers"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"
                    memory: "?*"
```

---

```yaml
metadata:
  name: require-resource-limits
```
- Policy name — shown in error messages when a pod without limits is blocked.

```yaml
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"
                    memory: "?*"
```
- `pattern` — the pod must have `resources.limits.cpu` and `resources.limits.memory` set.
- `"?*"` — Kyverno wildcard meaning "any non-empty value". The pod just needs to have something set — `500m`, `1`, `2000m` — anything. It just can't be missing.
- If either `cpu` or `memory` limit is absent, the pod is blocked.

This connects directly to our `values.yaml` — we set limits there:
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
```
Juice Shop will pass this policy. But if someone tries to deploy a pod without limits — Kyverno blocks it.

---

## disallow-latest-tag.yaml — Line by Line

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-image-tag
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Using 'latest' image tag is not allowed. Use an immutable tag like a commit SHA."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```

---

```yaml
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```
- `image: "!*:latest"` — Kyverno pattern syntax:
  - `*` — match any image name
  - `:latest` — ending with the latest tag
  - `!` — negate — the image must **NOT** match this pattern
- So: block any pod whose image ends with `:latest`

Examples:
- `nginx:latest` → **blocked**
- `nginx` (no tag, defaults to latest) → **blocked**
- `123456.dkr.ecr.ap-south-1.amazonaws.com/devsecops-eks-dev:abc123sha` → **allowed**

Our CI pipeline always uses `github.sha` as the tag — so Juice Shop always passes this policy.

---

## How all three policies connect

| Policy | Blocks | Our app |
|---|---|---|
| `disallow-root-user` | Containers running as root | Juice Shop must have `runAsNonRoot: true` |
| `require-resource-limits` | Pods without CPU/memory limits | Already set in `values.yaml` |
| `disallow-latest-tag` | Images tagged `:latest` | CI uses SHA tag — always passes |

---

## AWS session steps

```bash
# Install Kyverno
kubectl apply -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml

# Wait for Kyverno to be ready
kubectl wait --for=condition=ready pod -l app=kyverno -n kyverno --timeout=90s

# Apply all policies
kubectl apply -f kyverno-policies/

# List all policies
kubectl get clusterpolicy

# Check if a policy is active
kubectl describe clusterpolicy disallow-root-user
```

---

## How this fits in our DevSecOps pipeline

```
Phase 8  — ECR push     (image stored with SHA tag)
Phase 10 — Helm         (chart defines what runs)
Phase 9  — ArgoCD       (deploys the chart to EKS)
Phase 11 — Kyverno      (validates every pod before it runs) ← YOU ARE HERE
Phase 12 — Falco        (monitors pods at runtime)
Phase 13 — Vault        (injects secrets into pods)
Phase 14 — Prometheus   (monitors the running system)
```

Kyverno is **pre-runtime** — it catches bad configs before a single container starts.
Falco is **runtime** — it watches what containers do after they start.
Together they give you defence at two layers.
