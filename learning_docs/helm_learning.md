# Helm — Kubernetes Package Manager

---

## What is Helm?

Helm is the **package manager for Kubernetes**.

Just like:
- `apt` installs software on Ubuntu
- `npm` installs packages for Node.js
- `pip` installs libraries for Python

Helm installs **applications on Kubernetes** — but instead of a single binary, it manages a collection of Kubernetes YAML files as a single unit called a **chart**.

---

## The problem Helm solves

Without Helm, deploying an app to Kubernetes means managing many separate YAML files:

```
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
```

Problems with raw YAML:
- Every environment (dev/staging/prod) needs its own copy of every file
- Changing the image tag means editing multiple files manually
- No version tracking — you can't easily roll back to a previous state
- No standard way to package and share an app

**Helm solves all of this.**

---

## Where Helm fits in this pipeline

```
Code pushed to GitHub
        ↓
CI builds Docker image → pushes to ECR
        ↓
CI updates image tag in helm/values.yaml
        ↓
ArgoCD detects the Git change
        ↓
ArgoCD runs: helm install / helm upgrade
        ↓
Juice Shop is live on EKS ← Helm made this possible
```

Helm is the **packaging layer** — ArgoCD is just the delivery mechanism.
Without a Helm chart, ArgoCD has nothing to deploy.

---

## Core Concepts

### Chart

A **chart** is a Helm package. It's a folder containing:
- A `Chart.yaml` (metadata)
- A `values.yaml` (default configuration)
- A `templates/` folder (Kubernetes YAML files with placeholders)

Think of a chart like a **blueprint** for an application.

```
helm/
└── juice-shop/           ← this is the chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── deployment.yaml
        ├── service.yaml
        └── ingress.yaml
```

**Why the `juice-shop/` subfolder?**

The folder itself IS the chart. When you run `helm install my-release ./helm/juice-shop`, Helm looks for `Chart.yaml` inside that folder to confirm it's a valid chart.

More importantly, the subfolder-per-chart pattern scales when you add more apps:

```
helm/
├── juice-shop/        ← chart for Juice Shop
├── vault/             ← chart for Vault (Phase 13)
└── monitoring/        ← chart for Prometheus+Grafana (Phase 14)
```

If files were placed directly in `helm/`, there'd be no way to separate multiple charts. One subfolder per chart is a Helm convention, not optional.

---

### Values

`values.yaml` holds the **default configuration** for the chart.

```yaml
image:
  repository: 123456789.dkr.ecr.ap-south-1.amazonaws.com/devsecops-eks-dev
  tag: ""
replicaCount: 1
service:
  port: 3000
```

These values are injected into templates using Go templating syntax: `{{ .Values.image.repository }}`

You can **override values** at deploy time:
```bash
helm install juice-shop ./helm/juice-shop --set image.tag=abc123
```

This means one chart works for dev, staging, and prod — just pass different values.

---

### Templates

Templates are Kubernetes YAML files with **placeholders** (Go template syntax).

Example `deployment.yaml` template:
```yaml
spec:
  containers:
    - name: juice-shop
      image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
```

At deploy time, Helm substitutes the placeholders with actual values from `values.yaml` (or overrides).

**Common template functions:**

| Syntax | What it does |
|---|---|
| `{{ .Values.key }}` | Insert a value from values.yaml |
| `{{ .Release.Name }}` | Insert the Helm release name |
| `{{ .Chart.Name }}` | Insert the chart name |
| `{{ include "chart.name" . }}` | Call a named template (defined in `_helpers.tpl`) |
| `{{- if .Values.ingress.enabled }}` | Conditional block |
| `{{- range .Values.list }}` | Loop over a list |

---

### Release

A **release** is a deployed instance of a chart on a Kubernetes cluster.

```bash
helm install my-release ./helm/juice-shop
```

- `my-release` is the release name
- You can have multiple releases of the same chart (e.g., `juice-shop-dev`, `juice-shop-staging`)
- Helm tracks each release's history — you can roll back to any previous version

---

### Repository

A **Helm repository** is a collection of charts hosted remotely (like npm registry for Kubernetes).

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack
```

In this project, we write our **own chart** from scratch — we don't pull from a repo.

---

## Chart.yaml — Line by Line

```yaml
apiVersion: v2
name: juice-shop
description: OWASP Juice Shop deployment on EKS
type: application
version: 0.1.0
appVersion: "17.0.0"
```

---

This file is the **identity card** of the chart. Helm reads this first to know what it's dealing with.

```yaml
apiVersion: v2
```
Tells Helm which version of the chart format you're using.
- `v2` = Helm 3 format
- `v1` = old Helm 2 format (don't use this — Helm 2 is deprecated)
Always write `v2`.

```yaml
name: juice-shop
```
The name of this chart. Must match the folder name (`helm/juice-shop/`).
Helm uses this name in error messages, labels, and when listing charts.

```yaml
description: OWASP Juice Shop deployment on EKS
```
A human-readable description. Not used by Kubernetes — just for documentation and `helm search` output.

```yaml
type: application
```
Two possible values:
- `application` — a chart that deploys a running app (Deployment, Service, etc.) — **this is what we use**
- `library` — a chart that only contains reusable template helpers, never deployed directly

```yaml
version: 0.1.0
```
The version of the **chart itself** — not the app inside.
- Uses semantic versioning: `MAJOR.MINOR.PATCH`
- You bump this when you change the chart structure (add a new template, change a value name, etc.)
- `0.1.0` means: first version, not production-ready yet

```yaml
appVersion: "17.0.0"
```
The version of the **application** packaged inside the chart — in our case, OWASP Juice Shop v17.
- This is just informational — Kubernetes doesn't use it
- The actual image tag (the real version running) comes from `values.yaml`
- Written in quotes because YAML would otherwise try to parse it as a number

**`version` vs `appVersion` — the key difference:**
| Field | Tracks | Bump when |
|---|---|---|
| `version` | The chart (your Helm files) | You change Chart.yaml, values.yaml, or templates |
| `appVersion` | The app inside (Juice Shop) | Juice Shop releases a new version |

---

## values.yaml — Line by Line

```yaml
replicaCount: 1

image:
  repository: ""
  tag: ""
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 3000

ingress:
  enabled: false
  host: ""

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

---

This file holds the **default configuration** for the chart. Think of it as the settings panel — every value here can be overridden at deploy time without touching the templates.

```yaml
replicaCount: 1
```
How many identical pods (copies) of Juice Shop to run.
- `1` = one pod running at a time (fine for dev/testing)
- In production you'd set this to `2` or `3` for high availability
- Referenced in `deployment.yaml` as `{{ .Values.replicaCount }}`

```yaml
image:
  repository: ""
  tag: ""
  pullPolicy: IfNotPresent
```
The Docker image configuration. Three sub-fields:

- `repository: ""` — the ECR URL where the image lives (e.g. `123456789.dkr.ecr.ap-south-1.amazonaws.com/devsecops-eks-dev`). Left empty here because **CI fills this in** when deploying — it knows the account ID and region.

- `tag: ""` — the specific image version to run. Left empty here because **CI fills this in** with `github.sha` after every push. This is how ArgoCD always deploys the latest commit.

- `pullPolicy: IfNotPresent` — tells Kubernetes when to pull the image from ECR:
  | Value | Behaviour |
  |---|---|
  | `IfNotPresent` | Only pull if the image isn't already on the node (saves bandwidth) |
  | `Always` | Pull every time a pod starts (guarantees freshness) |
  | `Never` | Never pull — must already exist on node |
  We use `IfNotPresent` because our tags are immutable SHAs — the same tag always means the same image.

```yaml
service:
  type: ClusterIP
  port: 3000
```
How the app is exposed on the network:

- `type: ClusterIP` — the Service is only reachable **inside the cluster**. External traffic comes through the Ingress controller (not directly through the Service). This is the most secure default.

- `port: 3000` — Juice Shop listens on port 3000. The Service forwards traffic to this port on the pod.

```yaml
ingress:
  enabled: false
  host: ""
```
Controls whether an Ingress resource is created (external access):

- `enabled: false` — no Ingress created by default. The templates wrap the Ingress YAML in `{{- if .Values.ingress.enabled }}` so nothing is created unless you flip this to `true`.

- `host: ""` — the domain name (e.g. `juiceshop.example.com`). Left empty because we don't have a domain yet — this gets filled when the cluster is live.

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```
How much CPU and memory the container is allowed to use:

- `limits` — the **maximum** the container can ever use. If it tries to use more, Kubernetes kills it.
- `requests` — what Kubernetes **reserves** for this container on the node. Kubernetes uses this to decide which node to place the pod on.

CPU units:
- `500m` = 500 millicores = 0.5 of one CPU core
- `1000m` = 1 full CPU core

Memory units:
- `512Mi` = 512 mebibytes (~536 MB)

**Why set both?**
- Without `requests` — Kubernetes doesn't know how much space to reserve, pods get packed onto nodes badly
- Without `limits` — one misbehaving pod can consume all node resources and crash other pods
- This is also enforced by our **Kyverno policy** in Phase 11 — pods without resource limits will be blocked

---

## templates/deployment.yaml — Line by Line

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-juice-shop
  labels:
    app: {{ .Chart.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Chart.Name }}
  template:
    metadata:
      labels:
        app: {{ .Chart.Name }}
    spec:
      containers:
        - name: juice-shop
          image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 3000
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

---

The Deployment tells Kubernetes: "run this container, with this image, this many times."

```yaml
apiVersion: apps/v1
kind: Deployment
```
- `apiVersion: apps/v1` — which Kubernetes API group this resource belongs to. Deployments live in the `apps` group, version `v1`. Kubernetes uses this to know how to process the file.
- `kind: Deployment` — the type of Kubernetes resource. A Deployment manages pods — it creates them, restarts them if they crash, and handles rolling updates.

```yaml
metadata:
  name: {{ .Release.Name }}-juice-shop
  labels:
    app: {{ .Chart.Name }}
```
- `metadata` — information about the resource itself (not what it runs, just what it is)
- `name: {{ .Release.Name }}-juice-shop` — the name of this Deployment in Kubernetes. `{{ .Release.Name }}` is replaced by Helm with the release name you give at deploy time (e.g. `helm install my-app` → name becomes `my-app-juice-shop`). This avoids hardcoding so one chart can be deployed multiple times with different names.
- `labels` — key-value tags attached to this resource. Used for filtering, grouping, and selection.
- `app: {{ .Chart.Name }}` — sets a label `app=juice-shop`. Other resources (like the Service) use this label to find and connect to these pods.

```yaml
spec:
  replicas: {{ .Values.replicaCount }}
```
- `spec` — the desired state. Everything under here is what you want Kubernetes to create/maintain.
- `replicas` — how many identical pods to run. Pulled from `values.yaml` (`replicaCount: 1`). Kubernetes will always try to keep exactly this many pods running — if one crashes, it starts a new one automatically.

```yaml
  selector:
    matchLabels:
      app: {{ .Chart.Name }}
```
- `selector` — how the Deployment finds and manages its own pods. It looks for pods that have the label `app=juice-shop`.
- This **must match** `template.metadata.labels` below — if they don't match, the Deployment can't find its pods and Kubernetes will throw an error.

```yaml
  template:
    metadata:
      labels:
        app: {{ .Chart.Name }}
```
- `template` — the blueprint for every pod this Deployment creates.
- `metadata.labels` — every pod created by this Deployment gets the label `app=juice-shop`. This is how the `selector` above finds them, and how the Service routes traffic to them.

```yaml
    spec:
      containers:
        - name: juice-shop
          image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
```
- `spec` (inside template) — the actual pod spec — what containers to run.
- `containers` — a list of containers in the pod. We have one: Juice Shop.
- `name: juice-shop` — name of the container inside the pod (for logs, exec commands).
- `image` — the full Docker image to pull. At deploy time Helm substitutes:
  - `{{ .Values.image.repository }}` → ECR URL
  - `{{ .Values.image.tag }}` → the commit SHA (set by CI)
  - Result: `123456789.dkr.ecr.ap-south-1.amazonaws.com/devsecops-eks-dev:abc123sha`

```yaml
          imagePullPolicy: {{ .Values.image.pullPolicy }}
```
- When to pull the image from ECR. Comes from `values.yaml` (`IfNotPresent`).

```yaml
          ports:
            - containerPort: 3000
```
- `containerPort` — the port the app listens on **inside** the container. Juice Shop uses 3000. This is informational — it doesn't actually open or restrict any ports, but it documents intent and is used by some tools.

```yaml
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```
- Injects the CPU/memory limits and requests from `values.yaml`.
- `toYaml` — converts the `resources` object from values.yaml into valid YAML text.
- `nindent 12` — adds 12 spaces of indentation so it lines up correctly under `resources:`.
- `{{-` — the dash strips the leading newline/whitespace before the block, keeping the output clean.

---

## templates/service.yaml — Line by Line

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-juice-shop
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ .Chart.Name }}
  ports:
    - protocol: TCP
      port: {{ .Values.service.port }}
      targetPort: 3000
```

---

The Service gives pods a **stable internal network address**. Pods get a new IP every time they restart — the Service sits in front and always points to the right pod.

```yaml
apiVersion: v1
kind: Service
```
- `apiVersion: v1` — Services are in the core Kubernetes API (no group prefix, just `v1`).
- `kind: Service` — a stable network endpoint that routes traffic to matching pods.

```yaml
metadata:
  name: {{ .Release.Name }}-juice-shop
```
- The Service name. Other resources (like Ingress) reference the Service by this name to send traffic to it.

```yaml
spec:
  type: {{ .Values.service.type }}
```
- How this Service is exposed. Comes from `values.yaml` (`ClusterIP`).

**Service types:**
| Type | Accessible from | When to use |
|---|---|---|
| `ClusterIP` | Inside cluster only | Default — most secure, used with Ingress |
| `NodePort` | External via node IP + fixed port | Simple testing without a load balancer |
| `LoadBalancer` | External via cloud load balancer | Production direct exposure (costs money) |

We use `ClusterIP` — external traffic comes through the Ingress controller, not directly through this Service.

```yaml
  selector:
    app: {{ .Chart.Name }}
```
- The Service finds pods by this label — it routes traffic to any pod with `app=juice-shop`.
- This must match the `labels` set in `deployment.yaml` → `template.metadata.labels`.
- This is the **glue** between Service and Deployment — no hardcoded pod names needed.

```yaml
  ports:
    - protocol: TCP
      port: {{ .Values.service.port }}
      targetPort: 3000
```
- `protocol: TCP` — Juice Shop uses HTTP which runs over TCP.
- `port` — the port the Service listens on (3000, from `values.yaml`). Other services inside the cluster call Juice Shop on this port.
- `targetPort` — the port on the **pod** to forward traffic to (3000, Juice Shop's actual port).
- Traffic flow: `Ingress → Service:3000 → Pod:3000`

---

## templates/ingress.yaml — Line by Line

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-juice-shop
spec:
  rules:
    - host: {{ .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .Release.Name }}-juice-shop
                port:
                  number: {{ .Values.service.port }}
{{- end }}
```

---

The Ingress is the **front door** — routes external HTTP/HTTPS traffic into the cluster and forwards it to the right Service.

```yaml
{{- if .Values.ingress.enabled }}
...
{{- end }}
```
- A Helm conditional block. The entire Ingress resource is only created if `ingress.enabled: true` in `values.yaml`.
- Currently `false` — no Ingress is created until the cluster is live and we have a domain.
- `{{-` — the dash trims whitespace/newlines before the tag, keeping the rendered YAML clean.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
```
- `apiVersion: networking.k8s.io/v1` — Ingress lives in the `networking.k8s.io` API group.
- `kind: Ingress` — a routing rule that accepts external HTTP traffic and forwards it to a Service.

```yaml
metadata:
  name: {{ .Release.Name }}-juice-shop
```
- The Ingress name. Used by kubectl and the Ingress controller to identify this routing rule.

```yaml
spec:
  rules:
    - host: {{ .Values.ingress.host }}
```
- `rules` — list of routing rules. We have one rule.
- `host` — the domain name this rule applies to (e.g. `juiceshop.example.com`). Comes from `values.yaml`. The Ingress controller checks the HTTP `Host` header and routes accordingly.

```yaml
      http:
        paths:
          - path: /
            pathType: Prefix
```
- `paths` — URL path rules under this host.
- `path: /` — match all paths (everything starting with `/`).
- `pathType: Prefix` — treat `path` as a prefix match. Any URL starting with `/` matches — so all traffic to this host is forwarded. (Alternative: `Exact` — only matches that exact path.)

```yaml
            backend:
              service:
                name: {{ .Release.Name }}-juice-shop
                port:
                  number: {{ .Values.service.port }}
```
- `backend` — where to forward matched traffic.
- `service.name` — the name of the Service to send traffic to (must match `service.yaml` metadata name exactly).
- `port.number` — which port on the Service to hit (3000).
- Full traffic flow: `Internet → Ingress controller → Ingress rule → Service:3000 → Pod:3000`

---

## Key Helm Commands

```bash
# Install a chart (first time)
helm install juice-shop ./helm/juice-shop

# Upgrade an existing release (subsequent deploys)
helm upgrade juice-shop ./helm/juice-shop

# Install or upgrade (idempotent — safe to run repeatedly)
helm upgrade --install juice-shop ./helm/juice-shop

# Pass values at deploy time
helm upgrade --install juice-shop ./helm/juice-shop \
  --set image.tag=abc123sha \
  --set replicaCount=2

# Override with a separate values file (for different environments)
helm upgrade --install juice-shop ./helm/juice-shop \
  -f helm/values-prod.yaml

# Preview rendered YAML without deploying (dry run)
helm template juice-shop ./helm/juice-shop

# Check release status
helm status juice-shop

# List all releases
helm list

# Roll back to previous version
helm rollback juice-shop 1

# Uninstall a release
helm uninstall juice-shop
```

---

## helm template — your best debugging tool

Before applying to a cluster, always run:

```bash
helm template juice-shop ./helm/juice-shop --set image.tag=testsha123
```

This renders the final YAML with all values substituted — lets you catch mistakes without touching a cluster.

---

## How CI updates the image tag (GitOps pattern)

After pushing the Docker image to ECR, CI auto-updates `helm/juice-shop/values.yaml`:

```yaml
- name: Update image tag in Helm values
  run: |
    sed -i "s|tag:.*|tag: ${{ github.sha }}|" helm/juice-shop/values.yaml
    git config user.name "github-actions"
    git config user.email "actions@github.com"
    git add helm/juice-shop/values.yaml
    git commit -m "Update image tag to ${{ github.sha }}"
    git push
```

---

### Line by Line

**`- name: Update image tag in Helm values`**
Just the step name — what shows up in the GitHub Actions UI.

---

**`run: |`**
The `|` means "what follows is a multi-line shell script". All lines below run as one bash script on the runner VM.

---

**`sed -i "s|tag:.*|tag: ${{ github.sha }}|" helm/juice-shop/values.yaml`**

This is the key line. `sed` is a Linux text replacement tool.

Breaking the pattern `s|tag:.*|tag: ${{ github.sha }}|` down:
- `s` — substitute (find and replace)
- `|` — delimiter between parts. We use `|` instead of the usual `/` because the SHA value could contain `/` and would break the pattern
- `tag:.*` — find any line that starts with `tag:` followed by anything (`.*` = any characters)
- `tag: ${{ github.sha }}` — replace it with `tag:` + the actual commit SHA
- `-i` — edit the file in place (save changes directly to the file, don't just print output)

So in `values.yaml`, this line:
```yaml
tag: ""
```
Becomes:
```yaml
tag: abc123def456...
```

---

**`git config user.name "github-actions"`**
**`git config user.email "actions@github.com"`**

CI runners don't have a git identity by default. Git refuses to commit without a name and email. These two lines set a temporary identity just for this commit. The values don't need to be real — they just need to exist.

---

**`git add helm/juice-shop/values.yaml`**

Stage only the `values.yaml` file. We don't want to accidentally commit anything else that may have changed on the runner during the build or scan steps.

---

**`git commit -m "Update image tag to ${{ github.sha }}"`**

Creates a commit with the SHA in the message. This makes the git history readable — you can always trace which image version triggered which deployment.

---

**`git push`**

Pushes the commit back to the `main` branch on GitHub. This is what ArgoCD watches — when it sees this new commit, it picks up the new image tag and deploys the new version to EKS automatically. No manual `kubectl` or `helm` commands needed.

---

### Full flow

```
CI builds image → pushes to ECR with SHA tag
        ↓
sed replaces tag: "" → tag: abc123sha in values.yaml
        ↓
git commit + push → new commit lands on main
        ↓
ArgoCD detects the Git change
        ↓
ArgoCD runs helm upgrade with new tag
        ↓
New Juice Shop version live on EKS
```

Flow:
```
CI builds image → pushes to ECR with SHA tag
        ↓
CI updates helm/juice-shop/values.yaml: tag: <sha>
        ↓
CI commits and pushes values.yaml to Git
        ↓
ArgoCD detects the change in Git
        ↓
ArgoCD runs helm upgrade → new image deployed
```

This is the **GitOps pattern** — Git is the single source of truth.
No one manually runs `kubectl` or `helm` — everything flows from a Git commit.

---

## Helm 2 vs Helm 3

| Feature | Helm 2 | Helm 3 |
|---|---|---|
| Server component | Required Tiller (runs in cluster) | No server — client only |
| Security | Tiller had full cluster access (risky) | No Tiller — uses kubeconfig permissions |
| Release storage | ConfigMaps in kube-system | Secrets in the release namespace |
| `apiVersion` in Chart.yaml | `v1` | `v2` |

**Always use Helm 3.** Helm 2 is deprecated and Tiller was a major security risk.

---

## How this fits in our DevSecOps pipeline

| Phase | Tool | What it does |
|---|---|---|
| 8 | ECR push | Image stored with SHA tag |
| **10** | **Helm** | **Package the app as a K8s chart** |
| 9 | ArgoCD | Watch Git, run `helm upgrade` on change |
| 11 | Kyverno | Validate Helm-rendered manifests against policies |
| 12 | Falco | Monitor running pods (deployed by Helm) |
| 13 | Vault | Inject secrets into pods (deployed by Helm) |
| 14 | Prometheus | Scrape metrics from pods (deployed by Helm) |

Everything from Phase 9 onwards depends on Phase 10.
Helm is the packaging layer the entire deployment stack sits on top of.
