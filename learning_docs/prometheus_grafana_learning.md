# Prometheus + Grafana — Monitoring

---

## What is Prometheus?

Prometheus is an **open-source monitoring and alerting tool**.

Its job: **scrape metrics from your applications and infrastructure at regular intervals, store them, and let you query them.**

Think of Prometheus as a time-series database that continuously collects numbers — CPU usage, memory usage, HTTP request count, error rate — and stores them with timestamps.

---

## What is Grafana?

Grafana is an **open-source dashboarding tool**.

Its job: **connect to Prometheus (or other data sources) and visualize the metrics as graphs, charts, and dashboards.**

Prometheus collects and stores the data. Grafana makes it human-readable.

```
App / Kubernetes → Prometheus (collects) → Grafana (visualizes)
```

---

## The problem they solve

Without monitoring:
- You don't know a pod is using 95% memory until it crashes
- You don't know request error rates are climbing until users complain
- You can't tell if a deployment caused a performance regression
- You have no baseline to compare against

With Prometheus + Grafana:
- Real-time visibility into pod health, CPU, memory
- Alert before things break (not after)
- Compare metrics before and after a deployment
- One dashboard showing the entire system at a glance

---

## Where Prometheus + Grafana fit in this pipeline

```
Phase 9  — ArgoCD       (deploys Juice Shop)
Phase 11 — Kyverno      (validates pod configs)
Phase 13 — Vault        (injects secrets)
Phase 14 — Prometheus + Grafana (monitors everything) ← YOU ARE HERE
```

Monitoring comes last because you need a running, secured system to monitor. No point monitoring a broken one.

---

## How Prometheus works

### Scraping

Prometheus uses a **pull model** — it scrapes metrics from targets on a schedule (default: every 15 seconds).

```
Prometheus → HTTP GET /metrics → App or Kubernetes component
                    ↓
         Receives metrics in text format
                    ↓
         Stores in time-series database
```

Each target exposes a `/metrics` endpoint that returns metrics in Prometheus text format:
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET", status="200"} 1234
http_requests_total{method="POST", status="500"} 5
```

### Exporters

Not all systems natively expose `/metrics`. **Exporters** are small services that translate a system's metrics into Prometheus format.

| Exporter | What it monitors |
|---|---|
| `node-exporter` | Host/node CPU, memory, disk, network |
| `kube-state-metrics` | Kubernetes object state (pod counts, deployment health) |
| `blackbox-exporter` | HTTP endpoint availability (is the app responding?) |

In our stack, `kube-prometheus-stack` installs all of these automatically.

---

## kube-prometheus-stack

Instead of installing Prometheus and Grafana separately, we use the **kube-prometheus-stack** Helm chart — a single chart that installs:

- Prometheus
- Grafana
- Alertmanager (handles alert routing)
- node-exporter (node metrics)
- kube-state-metrics (K8s object metrics)
- Pre-built dashboards for Kubernetes

One Helm install gives you a complete monitoring stack.

---

## What we monitor in this project

| Metric | Why |
|---|---|
| Pod CPU usage | Detect runaway processes, right-size resources |
| Pod memory usage | Detect memory leaks before OOM kills |
| HTTP request rate | How much traffic Juice Shop is handling |
| HTTP error rate | Are users seeing errors? |
| Node health | Is the EKS worker node healthy? |
| Pod restart count | Frequently restarting pods = something is wrong |

---

## Files we create

### monitoring/prometheus-values.yaml

Helm values to configure the kube-prometheus-stack — enable/disable components, set retention, configure Grafana.

---

## prometheus-values.yaml — Line by Line

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        cpu: 200m
        memory: 400Mi
      limits:
        cpu: 500m
        memory: 1Gi

grafana:
  enabled: true
  adminPassword: "admin"
  service:
    type: ClusterIP

alertmanager:
  enabled: false

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
```

---

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
```
- `retention: 7d` — how long Prometheus keeps metric data. After 7 days, old data is deleted.
- More retention = more disk space. 7 days is enough for a portfolio project.
- In production you'd use longer retention (30-90 days) or remote storage (S3, Thanos).

```yaml
    resources:
      requests:
        cpu: 200m
        memory: 400Mi
      limits:
        cpu: 500m
        memory: 1Gi
```
- CPU and memory for the Prometheus pod itself.
- Prometheus can be memory-hungry — it stores all metrics in memory before flushing to disk.
- `1Gi` memory limit is sufficient for a small cluster with a few pods.
- This also satisfies our **Kyverno policy** — `require-resource-limits` — Prometheus pods have limits set.

```yaml
grafana:
  enabled: true
  adminPassword: "admin"
```
- `enabled: true` — install Grafana as part of this stack.
- `adminPassword: "admin"` — the default Grafana admin password. Fine for a portfolio project. In production, this would come from Vault.

```yaml
  service:
    type: ClusterIP
```
- Grafana Service type is `ClusterIP` — not exposed externally. We access it via `kubectl port-forward` during the AWS session.
- Same pattern as Juice Shop — internal only, no public load balancer.

```yaml
alertmanager:
  enabled: false
```
- Alertmanager handles routing alerts to Slack, PagerDuty, email etc.
- Disabled for simplicity — we're not setting up alert routing in this project.
- In production this would be enabled with Slack/PagerDuty webhooks configured.

```yaml
nodeExporter:
  enabled: true
```
- `node-exporter` runs as a DaemonSet — one pod per node.
- Collects host-level metrics: CPU, memory, disk I/O, network — for the EKS worker nodes.
- Without this, you'd only see pod-level metrics, not node-level health.

```yaml
kubeStateMetrics:
  enabled: true
```
- `kube-state-metrics` watches the Kubernetes API and exposes metrics about K8s objects:
  - How many pods are running vs desired
  - Deployment rollout status
  - Pod restart counts
  - Resource requests vs limits across the cluster
- Essential for understanding cluster health, not just individual pod metrics.

---

## How Grafana dashboards work

Grafana uses **PromQL** (Prometheus Query Language) to query metrics and display them.

Example queries for Juice Shop:

```promql
# CPU usage for Juice Shop pods
rate(container_cpu_usage_seconds_total{namespace="juice-shop"}[5m])

# Memory usage for Juice Shop pods
container_memory_usage_bytes{namespace="juice-shop"}

# HTTP request rate (if Juice Shop exposes metrics)
rate(http_requests_total{namespace="juice-shop"}[5m])

# Pod restart count
kube_pod_container_status_restarts_total{namespace="juice-shop"}
```

kube-prometheus-stack ships with **pre-built dashboards** for:
- Kubernetes cluster overview
- Node resource usage
- Pod resource usage
- Kubernetes deployment status

You import these in Grafana — no need to build dashboards from scratch.

---

## AWS session steps

```bash
# Add Prometheus community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring/prometheus-values.yaml

# Check all pods are running
kubectl get pods -n monitoring

# Access Grafana dashboard (port-forward to local machine)
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

# Open in browser: http://localhost:3000
# Username: admin
# Password: admin

# Access Prometheus UI
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090
# Open in browser: http://localhost:9090
```

---

## Prometheus vs Grafana — the difference

| | Prometheus | Grafana |
|---|---|---|
| What it does | Collects and stores metrics | Visualizes metrics |
| Interface | Query UI (PromQL) | Dashboards and graphs |
| Data storage | Yes — time-series DB | No — reads from Prometheus |
| Alerting | Yes — basic alerts | Yes — via Alertmanager |
| Can work alone? | Yes | No — needs a data source |

---

## How this fits in our DevSecOps pipeline

```
pipeline-info     → GitHub Actions basics
secret-scan       → Gitleaks (secrets detection)
sast              → SonarCloud (code vulnerabilities)
sca               → Trivy fs (dependency vulnerabilities)
iac-scan          → Checkov (IaC misconfigs)
build-scan-push   → Docker build + Trivy image + ECR push
Helm              → Package app for Kubernetes
ArgoCD            → GitOps deployment to EKS
Kyverno           → Policy enforcement (pre-runtime)
Vault             → Secrets management
Prometheus+Grafana → Monitoring and visibility ← YOU ARE HERE
```

Prometheus + Grafana close the loop — you've built, secured, and deployed the app. Now you watch it.
