# DevSecOps EKS Pipeline — Implementation Guide

This document explains the complete implementation of this project — what was built, why, and how each piece works together.
Use this as a reference during interviews to explain what was built and the decisions made.

---

## Project Goal

Build an end-to-end DevSecOps pipeline that secures a web application at every stage — from code commit to production deployment on AWS EKS — with security scanning, policy enforcement, GitOps deployment, and observability.

**Application used:** OWASP Juice Shop (intentionally vulnerable Node.js app)
- Frontend: Angular
- Backend: Node.js + Express
- Database: SQLite

---

## Architecture Overview

```
Developer pushes code
        ↓
GitHub Repository
        ↓
GitHub Actions CI/CD Pipeline
  ├── pipeline-info   → prints pipeline metadata
  ├── secret-scan     → Gitleaks (secrets detection)
  ├── sast            → SonarCloud (static code analysis)
  ├── sca             → Trivy fs (dependency scanning)
  ├── iac-scan        → Checkov (Terraform scanning)
  └── build-scan-push → Docker build + Trivy image scan + ECR push
        ↓
     ArgoCD (GitOps) — detects new image tag in values.yaml → deploys
        ↓
   AWS EKS Cluster
  ├── Kyverno         → admission policy enforcement
  └── Juice Shop pods → running from ECR image
        ↓
Prometheus + Grafana (monitoring)
```

---

## Phase 1 — Project Setup

### What was done
- Created GitHub repo `devsecops-eks-pipeline`
- Set up folder structure:
  ```
  .github/workflows/   → GitHub Actions pipeline
  app/                 → OWASP Juice Shop application + Dockerfile
  terraform/           → AWS infrastructure as code (modules + envs)
  helm/                → Kubernetes Helm chart for Juice Shop
  argocd/              → ArgoCD Application manifest
  kyverno-policies/    → Kubernetes admission policies
  vault/               → Vault policy + ServiceAccount
  monitoring/          → Prometheus + Grafana Helm values
  docs/                → Deployment guide and implementation guide
  ```
- Cloned OWASP Juice Shop into `app/` folder
- Removed Juice Shop's own `.git` so it becomes part of our repo
- Created `.gitignore` to prevent sensitive files from being committed
- Created `.gitleaks.toml` to allowlist known false positives in Juice Shop

### Key decisions
- Used OWASP Juice Shop because it is intentionally vulnerable — security scanners find real issues making the project realistic
- Kept repo public so SonarCloud is free and visible to recruiters

---

## Phase 2 — GitHub Actions (CI/CD Pipeline)

### What is GitHub Actions
GitHub Actions is a CI/CD platform built into GitHub. It runs automated tasks whenever something happens in the repo (push, PR, schedule).

### Pipeline structure
File: `.github/workflows/ci.yml`

All 6 jobs run sequentially — each job `needs` the previous one. If any job fails, all downstream jobs are skipped.

```
pipeline-info → secret-scan → sast → sca → iac-scan → build-scan-push
```

**Job 1 — pipeline-info:** Prints branch, SHA, actor, lists files. Quick sanity check.

**Job 2 — secret-scan:** Gitleaks scans full git history for leaked secrets. Runs first — no point scanning code with exposed credentials.

**Job 3 — sast:** SonarCloud scans source code for vulnerabilities, bugs, code smells without running the app.

**Job 4 — sca:** Trivy filesystem scan checks `package.json` dependencies for known CVEs.

**Job 5 — iac-scan:** Checkov scans Terraform files for AWS misconfigurations.

**Job 6 — build-scan-push:**
1. Build Docker image
2. Trivy image scan (CVEs in OS packages and libraries)
3. Authenticate to AWS via OIDC (keyless — no stored credentials)
4. Push image to ECR with git SHA as tag
5. Update `helm/juice-shop/values.yaml` with new repository + tag
6. Commit and push values.yaml back to GitHub → triggers ArgoCD

### OIDC Authentication (Industry Standard)
Instead of storing AWS credentials in GitHub Secrets, we use OIDC:

```
GitHub Actions starts job
        ↓
GitHub issues a signed JWT: "This is repo X, branch main"
        ↓
AWS verifies the JWT with GitHub's public key
        ↓
AWS checks: does an IAM Role trust this repo?
        ↓
YES → AWS issues short-lived credentials automatically
```

Zero stored secrets. Zero manual rotation. Industry standard approach.

---

## Phase 3 — Gitleaks (Secrets Detection)

Scans code and entire git history for hardcoded secrets — API keys, passwords, tokens, private keys.

**`.gitleaks.toml` allowlist:**
Juice Shop has intentional fake secrets (part of the CTF challenges). These paths are allowlisted to prevent false positives:
- `app/data/static`
- `app/frontend/src/assets`
- `app/data/datacreator.ts`
- `app/lib/insecurity.ts`
- `app/encryptionkeys` (JWT keys intentionally committed — part of official Juice Shop source)

---

## Phase 4 — SonarCloud (SAST)

Static Application Security Testing — analyzes source code WITHOUT running it.

**Scan results on Juice Shop** (expected — app is intentionally vulnerable):
- 486 open issues
- Security Rating: E (worst)
- 32 security vulnerabilities including SQL injection, XSS, hardcoded secrets

Pipeline is configured with `soft_fail` so it reports findings without blocking — the goal is visibility, not blocking an intentionally vulnerable app.

---

## Phase 5 — Trivy (SCA + Image Scan)

**Filesystem scan:** Checks `package.json` for vulnerable npm dependencies.

**Image scan:** After Docker build, scans the final image for CVEs in OS packages and libraries.

**`.trivyignore`:** Juice Shop has intentional CVEs (crypto-js, jsonwebtoken, lodash, vm2) that are part of the hacking challenges. These are explicitly ignored with justification comments.

**Checkov skips:** `CKV_AWS_38`, `CKV_AWS_39` — EKS public endpoint is intentionally enabled for dev access from laptop.

---

## Phase 6 — Terraform (Infrastructure as Code)

### Structure
```
terraform/
  modules/
    vpc/     → VPC, subnets, IGW, NAT Gateway, route tables, flow logs
    eks/     → EKS cluster, node group, IAM roles, KMS, launch template
    ecr/     → ECR repository with lifecycle policy
  envs/
    dev/
      main.tf      → calls all modules
      oidc.tf      → GitHub Actions OIDC provider + IAM role
      variables.tf → dev-specific values
```

### What gets created
- **VPC:** 4 subnets across 2 AZs — public (`10.0.1.0/24`, `10.0.2.0/24`) and private (`10.0.10.0/24`, `10.0.20.0/24`)
- **EKS cluster:** Kubernetes 1.31, KMS encrypted secrets, all control plane logs enabled
- **Node group:** 2x `t3.medium` in private subnets, IMDSv2 enforced via launch template
- **ECR:** IMMUTABLE image tags (prevents tag overwriting), lifecycle policy
- **OIDC:** GitHub Actions IAM role with least-privilege ECR push permissions only

### Security hardening applied
| Feature | Why |
|---|---|
| Private subnets for nodes | Nodes not directly internet-accessible |
| NAT Gateway | Nodes can reach internet (for ECR, S3) but aren't reachable |
| KMS encryption | EKS secrets encrypted at rest |
| IMDSv2 required | Protects against SSRF attacks on metadata endpoint |
| IMMUTABLE ECR tags | Prevents image tampering after push |
| OIDC auth | No static AWS credentials anywhere |
| VPC flow logs | Network traffic auditing |

---

## Phase 7 — Helm (Kubernetes Packaging)

Helm is the package manager for Kubernetes — bundles K8s manifests into a versioned, configurable chart.

### Chart structure
```
helm/juice-shop/
  Chart.yaml          → chart metadata (name, version, appVersion)
  values.yaml         → default configuration values
  templates/
    deployment.yaml   → Kubernetes Deployment
    service.yaml      → ClusterIP Service on port 3000
    ingress.yaml      → Ingress (disabled by default)
```

### Why Helm over plain kubectl apply
- Single command to deploy: `helm install juice-shop ./helm/juice-shop`
- Values can be overridden at deploy time without editing files
- ArgoCD integrates natively with Helm charts

---

## Phase 8 — ArgoCD (GitOps)

ArgoCD watches the GitHub repo and automatically syncs the cluster to match what's in git.

### How it works
1. CI pipeline updates `helm/juice-shop/values.yaml` with new image tag
2. CI commits and pushes values.yaml to GitHub
3. ArgoCD detects the new commit (polls every 3 minutes)
4. ArgoCD applies the updated Helm chart to EKS
5. New pod starts with the new image

### ArgoCD Application manifest (`argocd/application.yaml`)
```yaml
spec:
  syncPolicy:
    automated:
      prune: true      # delete resources removed from git
      selfHeal: true   # revert manual kubectl changes
```
`selfHeal: true` means if someone manually edits a resource in the cluster, ArgoCD immediately reverts it back to what's in git. Git is the single source of truth.

---

## Phase 9 — Kyverno (Policy Enforcement)

Kyverno is a Kubernetes admission controller — it intercepts every resource creation request and enforces policies before anything is allowed to run.

### Install method
Must use Helm (not `kubectl apply`) — Kyverno CRDs exceed Kubernetes's 262144 byte annotation limit when applied directly.

### 3 policies applied

**`disallow-latest-tag`** — blocks any image tagged `:latest`
- Why: `:latest` is mutable — you can't guarantee what code is running
- Pattern: `image: "!*:latest"`

**`disallow-root-user`** — blocks containers running as root
- Why: root in container = root on host if container escapes
- Pattern: `runAsNonRoot: true`

**`require-resource-limits`** — blocks pods without CPU/memory limits
- Why: without limits, one pod can starve all others (noisy neighbor problem)
- Pattern: `cpu: "?*"`, `memory: "?*"` (any non-empty value)

### Kyverno vs Prometheus install conflict
Kyverno `Enforce` mode blocks Prometheus's install jobs because they don't set resource limits. Solution: temporarily set affected policies to `Audit` mode during Prometheus installation, then revert to `Enforce`.

This is a real-world scenario — system tools often need policy exceptions.

---

## Phase 10 — Prometheus + Grafana (Monitoring)

Installed via `kube-prometheus-stack` Helm chart — bundles Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics.

### Components
| Component | What it does |
|---|---|
| Prometheus | Scrapes and stores metrics from all cluster components |
| Grafana | Visualizes metrics with dashboards |
| node-exporter | Collects CPU, memory, disk metrics from each node |
| kube-state-metrics | Collects K8s object metrics (pod counts, deployments, etc.) |

### Configuration (`monitoring/prometheus-values.yaml`)
- Retention: 7 days
- Alertmanager: disabled (not needed for portfolio)
- Grafana: enabled with pre-built Kubernetes dashboards

---

## Phase 11 — Vault (Secrets Management)

HashiCorp Vault provides centralized secrets management with dynamic credentials and Kubernetes-native auth.

### Files
- `vault/policies/vault-policy.hcl` — defines what paths the Juice Shop service can read
- `vault/vault-auth.yaml` — Kubernetes ServiceAccount for Juice Shop

### How Kubernetes auth works
1. Pod presents its ServiceAccount JWT token to Vault
2. Vault verifies the token with Kubernetes API
3. Vault checks if the ServiceAccount has a role binding
4. If yes → Vault issues a short-lived token granting access to `secret/data/juice-shop/*`

---

## Dockerfile — Security Hardening

```dockerfile
FROM node:24 AS installer        # multi-stage build
...
FROM gcr.io/distroless/nodejs24-debian13   # final image
USER 65532                       # non-root user
```

**Key security decisions:**
- **Multi-stage build:** Build dependencies not present in final image
- **Distroless base image:** No shell, no package manager, minimal attack surface
- **Non-root user (65532):** Container can't write to system files
- **IMDSv2 on nodes:** Complements container security at the infrastructure layer

---

## End-to-End Flow Summary

```
1. git push
        ↓
2. GitHub Actions runs 6-stage pipeline
   (Gitleaks → SonarCloud → Trivy → Checkov → Docker build → ECR push)
        ↓
3. CI updates helm/juice-shop/values.yaml with new image SHA
        ↓
4. ArgoCD detects values.yaml change → deploys new version to EKS
        ↓
5. Kyverno validates pod spec before it's allowed to run
        ↓
6. Pod starts → Prometheus scrapes metrics → Grafana displays dashboards
```

Security is enforced at every layer:
- **Code level:** Gitleaks + SonarCloud
- **Dependency level:** Trivy SCA
- **Infrastructure level:** Checkov + Terraform security hardening
- **Image level:** Trivy image scan + distroless base + non-root
- **Runtime level:** Kyverno policies + IMDSv2
- **Auth level:** OIDC (no stored credentials), KMS encryption, least-privilege IAM
