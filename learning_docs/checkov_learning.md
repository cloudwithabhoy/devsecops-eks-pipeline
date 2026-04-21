# Checkov — IaC Security Scanner

---

## What is Checkov?

Checkov is an open-source **static analysis tool** for Infrastructure as Code (IaC).
It scans your Terraform, CloudFormation, Kubernetes, Helm, ARM templates, and more — and checks them against **security and compliance best practices** before you deploy anything.

Built by Bridgecrew (now part of Palo Alto Networks).

---

## Where it fits in the pipeline

```
pipeline-info → secret-scan → sast → sca → iac-scan ← YOU ARE HERE
                                                  ↓
                                          build-scan (next)
```

- Runs **before** any `terraform apply`
- Catches misconfigs at the **code level**, not after infra is live
- Complements Trivy: Trivy scans app dependencies, Checkov scans infra code

---

## What kind of problems does Checkov catch?

| Category | Example |
|---|---|
| Encryption | S3 bucket with no encryption, EBS not encrypted |
| Access control | S3 bucket publicly accessible, IAM `*` wildcard permissions |
| Logging | CloudTrail not enabled, VPC flow logs disabled |
| Network | Security group open to 0.0.0.0/0 on port 22 or 3389 |
| EKS | Public API endpoint enabled, no secrets encryption |
| ECR | Scan on push disabled, image tag mutability allowed |
| IMDSv2 | EC2/node not enforcing IMDSv2 (SSRF risk) |
| KMS | Resources not using KMS or using default AWS keys |

---

## How Checkov works

1. Reads your `.tf` files (no AWS credentials needed — purely static)
2. Parses resources into an internal graph
3. Runs each resource through a library of **checks** (rules)
4. Each check maps to a policy ID like `CKV_AWS_58` (EKS secrets encryption)
5. Reports PASSED / FAILED / SKIPPED per check

---

## Check IDs — naming convention

| Prefix | Meaning |
|---|---|
| `CKV_AWS_` | AWS-specific checks |
| `CKV_K8S_` | Kubernetes checks |
| `CKV_GIT_` | Git/GitHub checks |
| `CKV2_AWS_` | Newer/graph-based AWS checks |

Example: `CKV_AWS_58` → EKS cluster should have secrets encryption enabled

---

## Key Checkov checks relevant to this project

| Check ID | What it validates |
|---|---|
| `CKV_AWS_58` | EKS cluster — KMS encryption for secrets |
| `CKV_AWS_39` | EKS cluster — no public endpoint |
| `CKV_AWS_172` | ECR — immutable image tags |
| `CKV_AWS_163` | ECR — scan on push enabled |
| `CKV_AWS_136` | ECR — KMS encryption |
| `CKV_AWS_79` | EC2/node — IMDSv2 enforced |
| `CKV_AWS_111` | IAM — no wildcard resource in policies |
| `CKV_AWS_130` | VPC — subnets not auto-assigning public IPs |

Our Terraform was written with security in mind, so most of these should PASS.

---

## Checkov output — reading results

```
Check: CKV_AWS_58: "Ensure Amazon EKS Secrets are encrypted"
  PASSED for resource: aws_eks_cluster.main
  File: /terraform/modules/eks/main.tf:45

Check: CKV_AWS_39: "Ensure Amazon EKS public endpoint disabled"
  PASSED for resource: aws_eks_cluster.main
  File: /terraform/modules/eks/main.tf:45
```

If something fails:
```
Check: CKV_AWS_111: "Ensure IAM policies do not use wildcards"
  FAILED for resource: aws_iam_role_policy.example
  File: /terraform/modules/eks/main.tf:20

        Resource: aws_iam_role_policy.example
        ...
```

---

## Checkov vs other tools

| Tool | What it scans | When |
|---|---|---|
| Gitleaks | Source code — hardcoded secrets | On every commit |
| SonarCloud | Source code — code quality + security bugs | On every commit |
| Trivy (fs) | App dependencies — known CVEs in packages | On every commit |
| **Checkov** | **IaC files — misconfigurations in Terraform** | **On every commit** |
| Trivy (image) | Docker image — CVEs inside the image | After build |

---

## GitHub Actions — how it runs

```yaml
- name: Run Checkov IaC scan
  uses: bridgecrewio/checkov-action@master
  with:
    directory: terraform/         # scan the whole terraform/ folder
    framework: terraform          # only run Terraform checks
    soft_fail: true               # don't block pipeline on failure (learning mode)
    output_format: cli            # human-readable output in logs
```

### `soft_fail: true` — why?

Our Terraform is written securely, but Checkov can flag things that are:
- Intentional design choices
- Not yet configured (e.g., missing S3 backend logging)
- False positives

`soft_fail: true` means the job **reports findings but does not fail the pipeline**.
Once you review results and suppress known false positives with `#checkov:skip`, you can set `soft_fail: false` to enforce the gate.

---

## Suppressing false positives — inline skip

If a check flags something intentional, suppress it in the Terraform file:

```hcl
resource "aws_eks_cluster" "main" {
  #checkov:skip=CKV_AWS_39: Private endpoint only — no public access needed in dev
  ...
}
```

Format: `#checkov:skip=CHECK_ID: reason`

---

## Checkov severity levels

Checkov doesn't have severity levels per check by default — it's PASS or FAIL.
But you can filter by severity using `--check` or `--skip-check` flags, or use
Bridgecrew platform integration to get severity metadata.

---

## Running Checkov locally

```bash
# Install
pip install checkov

# Scan terraform directory
checkov -d terraform/

# Scan a specific file
checkov -f terraform/modules/eks/main.tf

# Only run specific checks
checkov -d terraform/ --check CKV_AWS_58,CKV_AWS_39

# Skip specific checks
checkov -d terraform/ --skip-check CKV_AWS_111

# Output as JSON
checkov -d terraform/ -o json
```

---

## What happens in our pipeline

1. Code is pushed to `main`
2. After `sca` (Trivy) passes, `iac-scan` triggers
3. Checkov checks out the repo and scans `terraform/`
4. Results appear in the GitHub Actions log
5. `soft_fail: true` — pipeline continues even if findings exist
6. You review findings, add skip annotations for intentional choices
7. Eventually flip to `soft_fail: false` to enforce the security gate

---

## Summary

| Concept | Key point |
|---|---|
| What | Static analysis of Terraform for misconfigurations |
| When | Before any `terraform apply`, on every push |
| How | Reads .tf files, runs policy checks, no AWS creds needed |
| Output | PASSED / FAILED per check ID per resource |
| False positives | Suppress inline with `#checkov:skip=CKV_AWS_XXX: reason` |
| Gate enforcement | `soft_fail: true` for learning, `false` to block pipeline |
