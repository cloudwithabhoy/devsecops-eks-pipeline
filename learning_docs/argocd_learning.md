# ArgoCD — GitOps Continuous Delivery

---

## What is ArgoCD?

ArgoCD is a **continuous delivery tool for Kubernetes**.

Its one job: **watch a Git repository and make sure the cluster always matches what's in Git.**

If someone manually changes something in the cluster — ArgoCD detects the drift and reverts it back to what Git says. Git is always the source of truth.

---

## What is GitOps?

GitOps is a pattern where **Git is the single source of truth** for what should be running in your cluster.

Traditional approach (push-based):
```
Developer → runs kubectl apply → cluster changes
```
Problems:
- No audit trail of who changed what
- Manual steps — easy to forget or do wrong
- Cluster state can drift from what's in Git

GitOps approach (pull-based):
```
Developer → pushes to Git → ArgoCD pulls and applies → cluster changes
```
Benefits:
- Every change is a Git commit — full audit trail
- No one needs kubectl access to deploy
- Cluster always matches Git — no drift
- Roll back = `git revert`

---

## Where ArgoCD fits in this pipeline

```
Code pushed to GitHub
        ↓
CI: build → scan → push image to ECR
        ↓
CI: update image tag in helm/juice-shop/values.yaml → git push
        ↓
ArgoCD detects the new commit in Git  ← YOU ARE HERE
        ↓
ArgoCD runs: helm upgrade on EKS
        ↓
New Juice Shop version live
```

ArgoCD sits **between Git and the cluster**. CI handles building and pushing. ArgoCD handles deploying.

---

## How ArgoCD works

1. You install ArgoCD on the EKS cluster
2. You create an **Application** resource — tells ArgoCD which Git repo to watch and where to deploy
3. ArgoCD polls Git every 3 minutes (or you configure a webhook for instant sync)
4. When ArgoCD sees a new commit, it compares Git state vs cluster state
5. If they differ — it runs `helm upgrade` to bring the cluster in line with Git
6. If someone manually changes the cluster — ArgoCD reverts it (selfHeal)

---

## Core Concepts

### Application

An **Application** is the main ArgoCD resource. It tells ArgoCD:
- Which Git repo to watch
- Which path inside the repo contains the Helm chart
- Which cluster and namespace to deploy to
- How to sync (manual or automatic)

One Application = one app being managed by ArgoCD.

---

### Source

The **source** is where ArgoCD reads the desired state from — our GitHub repo + the `helm/` path.

```yaml
source:
  repoURL: https://github.com/your-org/devsecops-eks-pipeline
  targetRevision: main
  path: helm/juice-shop
```

- `repoURL` — the Git repository to watch
- `targetRevision` — which branch/tag/commit to track (`main` = always latest)
- `path` — the folder inside the repo that contains the Helm chart

---

### Destination

The **destination** is where ArgoCD deploys to — our EKS cluster and namespace.

```yaml
destination:
  server: https://kubernetes.default.svc
  namespace: juice-shop
```

- `server: https://kubernetes.default.svc` — means "deploy to the same cluster ArgoCD is running on" (in-cluster)
- `namespace` — the Kubernetes namespace to deploy Juice Shop into

---

### Sync Policy

Controls **how and when** ArgoCD applies changes.

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

- `automated` — ArgoCD syncs automatically when it detects a Git change. Without this, you'd have to click "Sync" manually in the UI every time.
- `prune: true` — if you delete a resource from Git (e.g. remove a Service), ArgoCD deletes it from the cluster too. Without this, deleted resources linger in the cluster forever.
- `selfHeal: true` — if someone manually changes the cluster (e.g. `kubectl edit`), ArgoCD detects the drift and reverts it back to what Git says. Enforces Git as the only way to make changes.

---

### Sync Status vs Health Status

ArgoCD tracks two separate statuses for every app:

| Status | What it means |
|---|---|
| **Synced** | Cluster matches Git exactly |
| **OutOfSync** | Git has changes not yet applied to cluster |
| **Healthy** | All pods are running and ready |
| **Degraded** | Pods are crashing or not ready |
| **Progressing** | Deployment is rolling out |

You want: `Synced` + `Healthy`

---

## application.yaml — Line by Line

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: juice-shop
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_GITHUB_USERNAME>/devsecops-eks-pipeline
    targetRevision: main
    path: helm/juice-shop
  destination:
    server: https://kubernetes.default.svc
    namespace: juice-shop
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
```
- `apiVersion: argoproj.io/v1alpha1` — ArgoCD adds its own custom resource types to Kubernetes. `Application` is one of them. `argoproj.io` is the API group ArgoCD registered — Kubernetes uses this to know which controller handles this resource.
- `kind: Application` — not a standard Kubernetes kind. Only exists after ArgoCD is installed on the cluster. When ArgoCD sees this, it knows "I need to manage this app."

```yaml
metadata:
  name: juice-shop
  namespace: argocd
```
- `name: juice-shop` — the name of this Application in ArgoCD. Shows up in the ArgoCD UI and CLI as `juice-shop`.
- `namespace: argocd` — ArgoCD watches **only** the `argocd` namespace for Application resources. If you put this in any other namespace, ArgoCD won't see it.

```yaml
spec:
  project: default
```
- ArgoCD uses Projects for grouping and access control. `default` is the built-in project — allows everything. In large teams you'd create separate projects per team to restrict who can deploy where.

```yaml
  source:
    repoURL: https://github.com/<YOUR_GITHUB_USERNAME>/devsecops-eks-pipeline
    targetRevision: main
    path: helm/juice-shop
```
- `repoURL` — the Git repo ArgoCD polls every 3 minutes. When a new commit lands here, ArgoCD compares it with what's running in the cluster.
- `targetRevision: main` — which branch to track. `main` means always follow the latest commit on main.
- `path: helm/juice-shop` — the folder inside the repo that contains the Helm chart. ArgoCD finds `Chart.yaml` here and knows to run `helm upgrade` — not raw `kubectl apply`.

```yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: juice-shop
```
- `server: https://kubernetes.default.svc` — "deploy to the same cluster I'm running on." This is the in-cluster Kubernetes API address. No external URL needed.
- `namespace: juice-shop` — the namespace where Juice Shop pods, services, and ingress will be created. Keeps Juice Shop isolated from ArgoCD and other tools.

```yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
- `automated` — without this, every time Git changes you'd have to manually click "Sync" in the ArgoCD UI. `automated` makes ArgoCD sync on its own.
- `prune: true` — if you delete a resource from Git (e.g. remove `ingress.yaml`), ArgoCD deletes it from the cluster too. Without this, deleted resources linger forever.
- `selfHeal: true` — if anyone runs `kubectl edit` directly on the cluster, ArgoCD detects the drift and reverts it back to what Git says. Enforces Git as the only way to make changes.

```yaml
    syncOptions:
      - CreateNamespace=true
```
- ArgoCD will create the `juice-shop` namespace automatically if it doesn't exist. Without this, the first deploy would fail with "namespace not found."

---

### Full flow

```
git push (CI updates values.yaml with new SHA)
        ↓
ArgoCD polls GitHub → detects new commit
        ↓
Reads helm/juice-shop/ → renders templates with new tag
        ↓
Runs helm upgrade on EKS → new pod starts in juice-shop namespace
        ↓
Old pod terminates → zero downtime rolling update
```

---

## How ArgoCD detects changes

ArgoCD polls Git every **3 minutes** by default.

For instant syncing, you configure a **webhook** — GitHub calls ArgoCD the moment a push happens:

```
git push → GitHub → webhook → ArgoCD → immediate sync
```

In our project we use the default polling (3 min) — fine for a portfolio project.

---

## ArgoCD UI

ArgoCD has a web dashboard. After installing on EKS:

```bash
# Port-forward the ArgoCD server to your local machine
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser
https://localhost:8080

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

The UI shows:
- All Applications and their sync/health status
- A visual tree of all Kubernetes resources (Deployment, Service, Ingress, pods)
- Sync history — every deployment with timestamp and Git commit
- One-click rollback to any previous version

---

## Key ArgoCD CLI Commands

```bash
# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && mv argocd /usr/local/bin/

# Login
argocd login localhost:8080

# List all applications
argocd app list

# Check app status
argocd app get juice-shop

# Manually trigger a sync
argocd app sync juice-shop

# Roll back to previous version
argocd app rollback juice-shop

# Delete an application
argocd app delete juice-shop
```

---

## ArgoCD vs manual kubectl/helm

| Action | Without ArgoCD | With ArgoCD |
|---|---|---|
| Deploy new version | `helm upgrade ...` manually | Push to Git → auto deploys |
| Roll back | `helm rollback ...` manually | `argocd app rollback` or `git revert` |
| Audit who deployed what | Check with teammates | Every deploy = a Git commit |
| Someone edits cluster manually | Change persists | ArgoCD reverts it |
| Namespace doesn't exist | Deploy fails | `CreateNamespace=true` handles it |

---

## How this fits in our DevSecOps pipeline

```
Phase 8  — ECR push         (image stored with SHA tag)
Phase 10 — Helm             (chart defines what runs)
Phase 9  — ArgoCD           (watches Git, deploys the chart) ← YOU ARE HERE
Phase 11 — Kyverno          (validates every resource ArgoCD deploys)
Phase 12 — Falco            (monitors pods ArgoCD deployed)
Phase 13 — Vault            (injects secrets into pods)
Phase 14 — Prometheus       (monitors the running system)
```

ArgoCD is the **deployment engine**. Everything after it (Kyverno, Falco, Vault, Prometheus) assumes the app is already running — which ArgoCD ensures.
