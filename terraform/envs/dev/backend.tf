terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment when S3 bucket is created for state storage
  # backend "s3" {
  #   bucket  = "devsecops-eks-terraform-state"
  #   key     = "dev/terraform.tfstate"
  #   region  = "ap-south-1"
  #   encrypt = true
  # }
}
