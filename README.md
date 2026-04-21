# DevSecOps EKS Pipeline

End-to-end DevSecOps pipeline securing OWASP Juice Shop from code commit to production deployment on AWS EKS — with automated security scanning, GitOps deployment, policy enforcement, and observability.

---

## Architecture Overview

```
Developer pushes code
        ↓
GitHub Repository
        ↓
GitHub Actions CI/CD Pipeline
  ├── Gitleaks       → Secrets detection
  ├── SonarCloud     → SAST (static code analysis)
  ├── Trivy (fs)     → SCA (dependency vulnerabilities)
  ├── Checkov        → IaC security (Terraform)
  ├── Docker Build
  └── Trivy (image)  → Container image scan
        ↓
    AWS ECR (image pushed only if all gates pass)
        ↓
     ArgoCD (GitOps — detects new image tag → deploys)
        ↓
   AWS EKS Cluster
  ├── Kyverno        → Admission policy enforcement
  └── Juice Shop pods running
        ↓
 Prometheus + Grafana (monitoring & dashboards)
```

---

## Application

**OWASP Juice Shop** — intentionally vulnerable Node.js web application used as the target for this DevSecOps pipeline.

| Tier | Technology |
|---|---|
| Frontend | Angular |
| Backend | Node.js + Express |
| Database | SQLite |

---

## Tool Stack

| Category | Tool | Purpose |
|---|---|---|
| CI/CD | GitHub Actions | Automated 6-stage pipeline |
| Secrets Detection | Gitleaks | Scan git history for leaked credentials |
| SAST | SonarCloud | Static code analysis for vulnerabilities |
| SCA + Image Scan | Trivy | Dependency and container image scanning |
| IaC Security | Checkov | Terraform misconfiguration scanning |
| Infrastructure | Terraform | AWS EKS + VPC + ECR provisioning |
| Container Registry | AWS ECR | Immutable-tagged container image storage |
| GitOps | ArgoCD | Automated deployment on git change |
| Packaging | Helm | Kubernetes manifest templating |
| Policy Enforcement | Kyverno | Kubernetes admission policies |
| Secrets Management | HashiCorp Vault | Centralized secrets with K8s auth |
| Monitoring | Prometheus + Grafana | Cluster metrics and dashboards |

---

## Project Structure

```
devsecops-eks-pipeline/
├── app/                        # OWASP Juice Shop + Dockerfile
├── .github/
│   └── workflows/ci.yml        # GitHub Actions pipeline
├── terraform/
│   ├── modules/
│   │   ├── vpc/                # VPC, subnets, NAT Gateway
│   │   ├── eks/                # EKS cluster + node group
│   │   └── ecr/                # ECR repository
│   └── envs/
│       └── dev/                # Dev environment (main.tf, oidc.tf)
├── helm/
│   └── juice-shop/             # Helm chart for Juice Shop
│       └── templates/          # Deployment, Service, Ingress
├── argocd/
│   └── application.yaml        # ArgoCD Application manifest
├── kyverno-policies/           # ClusterPolicy manifests
├── vault/
│   └── policies/               # Vault HCL policy + K8s ServiceAccount
├── monitoring/
│   └── prometheus-values.yaml  # kube-prometheus-stack Helm values
├── docs/
├── learning_docs/              # Learning notes for each tool
├── aws-deployment-plan.md      # Step-by-step AWS deployment guide
├── implementation-guide.md     # Full project implementation details
└── sonarcloud-setup.md         # SonarCloud setup guide
```

---

## Pipeline Stages

| Stage | Tool | What it checks |
|---|---|---|
| 1 — pipeline-info | — | Prints branch, SHA, actor |
| 2 — secret-scan | Gitleaks | Hardcoded secrets in code + git history |
| 3 — sast | SonarCloud | Security vulnerabilities, bugs, code smells |
| 4 — sca | Trivy (fs) | Vulnerable npm dependencies |
| 5 — iac-scan | Checkov | Terraform misconfigurations |
| 6 — build-scan-push | Docker + Trivy + ECR | Build image → scan → push to ECR → update Helm values |

---

## Kyverno Policies

| Policy | Action |
|---|---|
| `disallow-latest-tag` | Blocks any image tagged `:latest` |
| `disallow-root-user` | Blocks containers running as root |
| `require-resource-limits` | Blocks pods without CPU/memory limits |

---

## Security Highlights

- **OIDC auth** — GitHub Actions authenticates to AWS without any stored credentials
- **KMS encryption** — EKS secrets encrypted at rest
- **IMDSv2** — EC2 metadata endpoint hardened against SSRF
- **Distroless base image** — no shell, no package manager in final container
- **Non-root container** — Juice Shop runs as UID 65532
- **Immutable ECR tags** — images cannot be overwritten after push
- **VPC flow logs** — all network traffic audited

---

## Getting Started

1. **Read** [implementation-guide.md](implementation-guide.md) to understand the full project
2. **Follow** [aws-deployment-plan.md](aws-deployment-plan.md) to deploy step-by-step
3. **Reference** [learning_docs/](learning_docs/) for tool-specific learning notes

> **Cost:** ~$1-2 for a 2-hour session. Destroy immediately after screenshots.

---

## Prerequisites

- AWS account with SSO configured
- GitHub account with SonarCloud connected
- Tools installed: AWS CLI, Terraform, kubectl, Helm
- GitHub Secrets set: `AWS_ROLE_ARN`, `AWS_ACCOUNT_ID`, `SONAR_TOKEN`
