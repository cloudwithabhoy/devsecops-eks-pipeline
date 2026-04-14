variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "devsecops-eks"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}
