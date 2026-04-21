# AWS Deployment Guide — DevSecOps EKS Pipeline

> **Goal:** Deploy the full DevSecOps pipeline on AWS EKS, verify everything works, take screenshots, destroy.
> **Estimated time:** 2-3 hours
> **Estimated cost:** $1-2
> **Region:** ap-south-1 (Mumbai)

---

## Prerequisites

- AWS CLI, Terraform, kubectl, Helm installed
- AWS SSO configured with your profile name (referred to as `<YOUR_SSO_PROFILE>` throughout this guide)
- GitHub Secrets already set: `AWS_ROLE_ARN`, `AWS_ACCOUNT_ID`
- All code pushed to GitHub (CI pipeline passing)

---

## Phase 1 — AWS SSO Login

```bash
# Login via SSO (opens browser)
aws sso login --profile <YOUR_SSO_PROFILE>

# Set profile for all commands in this terminal session
export AWS_PROFILE=<YOUR_SSO_PROFILE>

# Verify credentials
aws sts get-caller-identity --profile <YOUR_SSO_PROFILE>
```

Expected output: your Account ID and SSO role ARN.

> **Important:** SSO sessions expire. If you get auth errors mid-session, run `aws sso login --profile <YOUR_SSO_PROFILE>` again. Do NOT cancel a running `terraform apply` — login in a separate terminal.

---

## Phase 2 — Terraform: Provision Infrastructure

```bash
cd terraform/envs/dev

# Initialize Terraform
terraform init

# Preview what will be created — verify 30 resources, 0 conflicts
terraform plan

# Apply — takes 15-25 minutes (EKS node group is slow)
terraform apply
# Type: yes when prompted
```

**What gets created (30 resources):**
- VPC with 4 subnets: `10.0.1.0/24`, `10.0.2.0/24` (public), `10.0.10.0/24`, `10.0.20.0/24` (private)
- Internet Gateway, NAT Gateway, route tables
- EKS cluster (`devsecops-eks-dev-cluster`) with KMS encryption
- EKS node group (2x `t3.medium` in private subnets)
- ECR repository (`devsecops-eks-dev`)
- IAM roles, KMS keys, CloudWatch log groups, VPC flow logs
- OIDC provider + GitHub Actions IAM role (keyless auth)

**After apply — note the output:**
```
github_actions_role_arn = "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/devsecops-eks-dev-github-actions"
```

---

## Phase 3 — Connect kubectl to EKS

```bash
aws eks update-kubeconfig --name devsecops-eks-dev-cluster --region ap-south-1 --profile <YOUR_SSO_PROFILE>
```

**Enable public endpoint access** (cluster is private by default — your laptop can't reach it):
```bash
aws eks update-cluster-config --name devsecops-eks-dev-cluster --region ap-south-1 --profile <YOUR_SSO_PROFILE> --resources-vpc-config '{"endpointPublicAccess": true, "endpointPrivateAccess": true}'
```

Wait ~5 minutes, then verify:
```bash
kubectl get nodes
```

Expected: 2 nodes in `Ready` state.

> **Note:** In Git Bash on Windows, the `--resources-vpc-config` value must be passed as JSON with single quotes: `'{"endpointPublicAccess": true, "endpointPrivateAccess": true}'`

---

## Phase 4 — Trigger CI Pipeline

The pipeline uses OIDC — no stored AWS credentials needed. Just push:

```bash
git commit --allow-empty -m "trigger pipeline"
git push
```

**Pipeline stages (in order):**
```
pipeline-info → secret-scan (Gitleaks) → sast (SonarCloud) → sca (Trivy fs) → iac-scan (Checkov) → build-scan-push
```

The `build-scan-push` job:
1. Builds Docker image from `app/`
2. Scans with Trivy (ignores intentional Juice Shop CVEs via `.trivyignore`)
3. Authenticates to AWS via OIDC (no keys stored in GitHub)
4. Pushes image to ECR with SHA tag
5. Updates `helm/juice-shop/values.yaml` with new image repository + tag
6. Commits and pushes values.yaml back to GitHub

Verify image was pushed:
```bash
aws ecr describe-images --repository-name devsecops-eks-dev --region ap-south-1 --profile <YOUR_SSO_PROFILE>
```

---

## Phase 5 — Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all 7 pods to be Running
kubectl get pods -n argocd
```

Apply the Juice Shop application:
```bash
# Run from project root
cd ~/path/to/devsecops-eks-pipeline
kubectl apply -f argocd/application.yaml

# Check status
kubectl get application -n argocd
```

Expected: `SYNC STATUS: Synced` and `HEALTH STATUS: Healthy`

Check Juice Shop pod:
```bash
kubectl get pods -n juice-shop
```

Expected: `1/1 Running`

Access ArgoCD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
# Username: admin
# Password:
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## Phase 6 — Install Kyverno

> **Important:** Do NOT use `kubectl apply` with the GitHub URL — Kyverno CRDs are too large (hits 262144 byte annotation limit). Use Helm.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace

# Wait for pods
kubectl get pods -n kyverno
```

Apply the 3 security policies:
```bash
kubectl apply -f kyverno-policies/
kubectl get clusterpolicy
```

Expected: 3 policies all `Ready`:
- `disallow-latest-tag` — blocks `:latest` image tags
- `disallow-root-user` — blocks containers running as root
- `require-resource-limits` — blocks pods without CPU/memory limits

---

## Phase 7 — Install Prometheus + Grafana

> **Important:** Kyverno will block Prometheus installation because its install jobs don't have resource limits. Temporarily switch to Audit mode first.

```bash
# Set policies to Audit (detect but don't block)
kubectl patch clusterpolicy disallow-root-user --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'
kubectl patch clusterpolicy require-resource-limits --type merge -p '{"spec":{"validationFailureAction":"Audit"}}'

# Install Prometheus + Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/prometheus-values.yaml

# Wait for pods
kubectl get pods -n monitoring

# Set policies back to Enforce
kubectl patch clusterpolicy disallow-root-user --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
kubectl patch clusterpolicy require-resource-limits --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
```

Access Grafana:
```bash
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Open: http://localhost:3000
# Username: admin
# Password:
kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
```

---

## Phase 8 — Access Juice Shop Frontend

```bash
kubectl port-forward svc/juice-shop-juice-shop -n juice-shop 8888:3000
# Open: http://localhost:8888
```

---

## Phase 9 — Screenshots for Portfolio

| Screenshot | How to get it |
|---|---|
| GitHub Actions — all stages green | GitHub repo → Actions tab |
| ArgoCD — juice-shop Synced + Healthy | `https://localhost:8080` |
| ArgoCD — resource tree | Click juice-shop app → resource tree view |
| Kyverno policies | `kubectl get clusterpolicy` |
| Juice Shop frontend | `http://localhost:8888` |
| Grafana — cluster dashboard | Dashboards → Kubernetes → Compute Resources → Cluster |
| Grafana — node metrics | Dashboards → Node Exporter |
| EKS nodes | `kubectl get nodes` |
| ECR repository | AWS Console → ECR |
| AWS Console — EKS cluster | AWS Console → EKS |
| AWS Console — VPC | AWS Console → VPC |

---

## Phase 10 — Destroy Everything

> **Do this immediately after screenshots. Do not leave running.**

```bash
cd terraform/envs/dev
export AWS_PROFILE=<YOUR_SSO_PROFILE>
terraform destroy
# Type: yes
```

If ECR destroy fails (repository not empty):
```bash
aws ecr delete-repository --repository-name devsecops-eks-dev --region ap-south-1 --profile <YOUR_SSO_PROFILE> --force
terraform destroy
# Type: yes again
```

Verify everything is gone:
```bash
aws eks list-clusters --region ap-south-1 --profile <YOUR_SSO_PROFILE>
# Expected: empty

aws ecr describe-repositories --region ap-south-1 --profile <YOUR_SSO_PROFILE>
# Expected: empty

aws ec2 describe-vpcs --region ap-south-1 --profile <YOUR_SSO_PROFILE> --query "Vpcs[?IsDefault==\`false\`].VpcId"
# Expected: empty
```

---

## Troubleshooting

### Terraform Issues

| Problem | Cause | Fix |
|---|---|---|
| `No valid credential sources found` | AWS_PROFILE not set | `export AWS_PROFILE=<YOUR_SSO_PROFILE>` |
| `InvalidSubnet.Conflict` | Orphaned subnet from previous failed apply | `aws ec2 describe-subnets --filters "Name=cidrBlock,Values=10.0.20.0/24" --region ap-south-1 --profile <YOUR_SSO_PROFILE> --query "Subnets[*].SubnetId"` then delete it |
| `NodeCreationFailure` | NAT Gateway not set up (VPC incomplete) | Fix subnet CIDRs, destroy VPC+EKS, reapply |
| State file locked | Another terminal holding the lock | Close other terminals, retry |
| SSO expired mid-apply | Session timeout | `aws sso login --profile <YOUR_SSO_PROFILE>` in separate terminal, don't cancel apply |

### kubectl Issues

| Problem | Cause | Fix |
|---|---|---|
| `i/o timeout` on `kubectl get nodes` | EKS has private endpoint only | Enable public endpoint: `aws eks update-cluster-config ... '{"endpointPublicAccess": true, "endpointPrivateAccess": true}'` |
| `--resources-vpc-config: expected one argument` | Git Bash parsing issue | Use JSON format with single quotes |

### Pod Issues

| Problem | Cause | Fix |
|---|---|---|
| `ENOENT: encryptionkeys/jwt.pub` | encryptionkeys/ not committed to git | `git add app/encryptionkeys/` and push |
| `ENOENT: .well-known/csaf/provider-metadata.json` | Directory missing | Add `mkdir -p .well-known/csaf && touch .well-known/csaf/provider-metadata.json` to Dockerfile |
| `CrashLoopBackOff` | Check logs | `kubectl logs -n juice-shop <pod-name> --previous` |

### Kyverno Issues

| Problem | Cause | Fix |
|---|---|---|
| `annotation size too large` on kubectl apply | CRD too large for direct apply | Use Helm instead |
| `invalid ownership metadata` on helm install | Leftover resources from failed kubectl apply | Delete CRDs, ClusterRoles, ClusterRoleBindings with `kyverno` label, then helm install |
| Kyverno blocks Prometheus install | Prometheus jobs don't have security context | Switch policies to Audit mode, install, switch back to Enforce |

### CI Pipeline Issues

| Problem | Cause | Fix |
|---|---|---|
| `Credentials could not be loaded` | OIDC not configured or wrong role ARN | Check `AWS_ROLE_ARN` secret, verify OIDC terraform resources exist |
| Trivy blocks on CVEs | Intentional Juice Shop vulnerabilities | Add CVEs to `.trivyignore` |
| Checkov fails on EKS public endpoint | `endpoint_public_access = true` | Skip `CKV_AWS_38,CKV_AWS_39` in ci.yml |
| Gitleaks blocks encryption keys | Keys not in allowlist | Add `app/encryptionkeys` to `.gitleaks.toml` allowlist |

---

## Cost Breakdown

| Resource | Duration | Estimated Cost |
|---|---|---|
| EKS cluster | ~2 hours | ~$0.20 |
| EC2 t3.medium x2 | ~2 hours | ~$0.10 |
| NAT Gateway | ~2 hours | ~$0.10 |
| ECR storage | ~2 hours | ~$0.01 |
| **Total** | | **~$0.50 - $1.00** |

---

## Quick Reference Commands

```bash
# Check all pods across all namespaces
kubectl get pods -A

# Check all Helm releases
helm list -A

# Check ArgoCD app status
kubectl get application -n argocd

# Check Kyverno policies
kubectl get clusterpolicy

# Stream Juice Shop logs
kubectl logs -f -n juice-shop deployment/juice-shop-juice-shop

# Get Grafana password
kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d

# Get ArgoCD password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Port-forward ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Port-forward Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Port-forward Juice Shop
kubectl port-forward svc/juice-shop-juice-shop -n juice-shop 8888:3000
```
