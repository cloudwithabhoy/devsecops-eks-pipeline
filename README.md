# DevSecOps EKS Pipeline

End-to-end DevSecOps pipeline with GitHub Actions, SonarQube, Trivy, ArgoCD, and Falco — securing a 3-tier app from code to EKS production deployment.

---

## Architecture Overview

```
Developer Workstation
        │
        ▼
  GitHub Repository
        │
        ▼
 GitHub Actions CI/CD
  ├── Gitleaks       → Secrets Detection
  ├── SonarQube      → SAST (Static Code Analysis)
  ├── Trivy (fs)     → SCA (Dependency Vulnerabilities)
  ├── Checkov        → IaC Security (Terraform)
  ├── Docker Build
  └── Trivy (image)  → Container Image Scan
        │
        ▼ (only if all gates pass)
    AWS ECR
  (Container Registry)
        │
        ▼
     ArgoCD
  (GitOps Deployment)
        │
        ▼
   AWS EKS Cluster
  ├── Kyverno        → Admission Policy Enforcement
  ├── Falco          → Runtime Threat Detection
  └── Vault          → Secrets Management
        │
        ▼
 Prometheus + Grafana
  (Monitoring & Security Dashboards)
```

---

## Application

**OWASP Juice Shop** — an intentionally vulnerable 3-tier web application used as the target for this DevSecOps pipeline.

| Tier | Technology |
|---|---|
| Frontend | Angular |
| Backend | Node.js + Express |
| Database | PostgreSQL |

---

## DevSecOps Tool Stack

| Category | Tool | Purpose |
|---|---|---|
| CI/CD | GitHub Actions | Automated pipeline |
| Secrets Detection | Gitleaks | Scan for leaked secrets in code |
| SAST | SonarQube | Static code analysis |
| SCA + Image Scan | Trivy | Dependency and container scanning |
| IaC Security | Checkov | Terraform security scanning |
| Infrastructure | Terraform | EKS cluster provisioning |
| Container Registry | AWS ECR | Store and scan container images |
| GitOps | ArgoCD | Automated deployment to EKS |
| Packaging | Helm | Kubernetes manifest templating |
| Policy Enforcement | Kyverno | Kubernetes admission policies |
| Runtime Security | Falco | Real-time threat detection on EKS |
| Secrets Management | HashiCorp Vault | Dynamic secrets, no hardcoded credentials |
| Monitoring | Prometheus + Grafana | Metrics and security dashboards |

---

## Project Structure

```
devsecops-eks-pipeline/
├── app/                        # OWASP Juice Shop application
├── .github/
│   └── workflows/              # GitHub Actions pipeline YAMLs
├── terraform/
│   ├── modules/
│   │   ├── eks/                # EKS cluster module
│   │   ├── vpc/                # VPC networking module
│   │   └── ecr/                # ECR repository module
│   └── envs/
│       ├── dev/                # Dev environment config
│       └── prod/               # Prod environment config
├── helm/
│   └── juice-shop/             # Helm chart for Juice Shop
│       └── templates/          # K8s manifest templates
├── kyverno-policies/           # Kubernetes admission policies
├── falco-rules/                # Custom Falco detection rules
├── vault/
│   └── policies/               # Vault access policies
├── monitoring/
│   ├── dashboards/             # Grafana dashboard JSONs
│   └── alerts/                 # Prometheus alert rules
└── docs/                       # Architecture diagrams and notes
```

---

## Pipeline Stages

### Stage 1 — Secrets Detection
- Tool: **Gitleaks**
- Scans every commit for hardcoded secrets, API keys, passwords
- Pipeline fails if any secret is detected

### Stage 2 — Static Code Analysis (SAST)
- Tool: **SonarQube**
- Analyzes source code for security vulnerabilities, bugs, code smells
- Quality gate: pipeline fails on any CRITICAL or BLOCKER issue

### Stage 3 — Dependency Scanning (SCA)
- Tool: **Trivy (filesystem mode)**
- Scans `package.json`, `requirements.txt` etc. for known CVEs
- Pipeline fails on CRITICAL severity findings

### Stage 4 — IaC Security Scanning
- Tool: **Checkov**
- Scans Terraform code for misconfigurations before infrastructure is created
- Pipeline fails on HIGH/CRITICAL policy violations

### Stage 5 — Container Image Build + Scan
- Tool: **Docker + Trivy (image mode)**
- Builds Docker image and scans it for OS and library vulnerabilities
- Pipeline fails on CRITICAL CVEs in the image

### Stage 6 — Push to ECR
- Only reached if all above stages pass
- Image pushed to AWS ECR with build SHA as tag
- No `latest` tag allowed (enforced by Kyverno)

### Stage 7 — GitOps Deployment via ArgoCD
- ArgoCD detects new image tag in Helm chart
- Deploys to EKS automatically
- Kyverno policies validate every manifest before pod creation

---

## Security Policies (Kyverno)

| Policy | Effect |
|---|---|
| Block images not from ECR | Deny |
| Require non-root containers | Enforce |
| Require resource limits on all pods | Enforce |
| Block `latest` image tag | Deny |
| Require read-only root filesystem | Enforce |

---

## Getting Started

> Each phase has its own setup guide inside `docs/`

- [Phase 1 — GitHub Actions Setup](docs/phase-1-github-actions.md)
- [Phase 2 — SonarQube Setup](docs/phase-2-sonarqube.md)
- [Phase 3 — Trivy Setup](docs/phase-3-trivy.md)
- [Phase 4 — Checkov Setup](docs/phase-4-checkov.md)
- [Phase 5 — Terraform EKS](docs/phase-5-terraform-eks.md)
- [Phase 6 — ArgoCD GitOps](docs/phase-6-argocd.md)
- [Phase 7 — Kyverno + Falco](docs/phase-7-kyverno-falco.md)
- [Phase 8 — HashiCorp Vault](docs/phase-8-vault.md)
- [Phase 9 — Prometheus + Grafana](docs/phase-9-monitoring.md)
