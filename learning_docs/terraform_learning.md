# Terraform — Learning Notes

---

## 1. What is Terraform?

Terraform is an Infrastructure as Code (IaC) tool by HashiCorp.
It lets you define cloud infrastructure (VPC, EKS, S3, EC2 etc.) in code
instead of clicking through the AWS console.

**In simple terms:**
> "Write code → Terraform talks to AWS API → infrastructure gets created"

---

## 2. Why IaC?

| Manual (Console) | IaC (Terraform) |
|---|---|
| Click through AWS console | Write code |
| Hard to repeat exactly | Run same code 100 times → same result |
| No history of changes | Git tracks every change |
| Easy to make mistakes | Reviewed like any other code |
| Cannot be scanned for security | Checkov scans for misconfigurations |

---

## 3. Core Concepts

### Provider
Tells Terraform which cloud to talk to (AWS, GCP, Azure etc.)
```hcl
provider "aws" {
  region = "us-east-1"
}
```

### Resource
A piece of infrastructure you want to create
```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
```
Format: `resource "resource_type" "local_name"`

### Variable
Makes your code reusable — values passed in at runtime
```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
```

### Output
Values returned after infrastructure is created
```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}
```

### Module
A reusable group of resources — like a function in programming
```hcl
module "vpc" {
  source = "../../modules/vpc"
  cidr   = "10.0.0.0/16"
}
```

### State File (terraform.tfstate)
Terraform saves the current state of infrastructure in a state file.
This file can contain sensitive data — NEVER commit it to git.
In production, store it in S3 with encryption.

---

## 4. Basic Commands

```bash
terraform init      # download providers and modules
terraform plan      # show what will be created/changed/destroyed
terraform apply     # actually create the infrastructure
terraform destroy   # destroy all infrastructure
terraform validate  # check syntax of .tf files
terraform fmt       # format code consistently
```

---

## 5. Our Project Structure

```
terraform/
├── modules/              # reusable modules
│   ├── vpc/              # VPC + subnets + routing
│   ├── eks/              # EKS cluster + node groups
│   └── ecr/              # ECR container registry
└── envs/
    └── dev/              # dev environment — calls all modules
        ├── main.tf       # calls vpc, eks, ecr modules
        ├── variables.tf  # input variables
        ├── backend.tf    # where to store state file (S3)
        └── terraform.tfvars  # actual values — in .gitignore
```

**Why modules?**
Instead of writing all resources in one file, modules separate concerns.
VPC module only knows about networking. EKS module only knows about the cluster.
Same module can be reused for dev, staging, prod environments.

---

## 6. What We Are Building

```
AWS
└── VPC (10.0.0.0/16)
    ├── Public Subnets  (2 AZs) → Load Balancer
    └── Private Subnets (2 AZs) → EKS Worker Nodes
            ↓
        EKS Cluster
        ├── Private API endpoint (not exposed to internet)
        ├── KMS encryption for secrets at rest
        └── Node Group (EC2 instances running pods)
            ↓
        ECR Repository
        └── Stores Docker images built by CI pipeline
```

---

## 7. Security Best Practices in Our Terraform

| Practice | Why |
|---|---|
| EKS API endpoint private only | Cluster not accessible from internet |
| KMS encryption for K8s secrets | Secrets encrypted at rest |
| IMDSv2 enforced on nodes | Prevents SSRF attacks on metadata service |
| Private subnets for worker nodes | Nodes not directly exposed to internet |
| S3 backend with encryption | State file (contains sensitive data) encrypted |
| No hardcoded credentials | Use IAM roles, not access keys |

---

## 8. Key Things to Remember

- `terraform.tfvars` → contains real values → ALWAYS in .gitignore
- `terraform.tfstate` → contains infrastructure state → ALWAYS in .gitignore
- `.terraform/` folder → downloaded providers → ALWAYS in .gitignore
- `terraform plan` before `terraform apply` — always review changes first
- Modules make code DRY (Don't Repeat Yourself) — reuse across environments
- `backend.tf` defines where state is stored — use S3 in production
