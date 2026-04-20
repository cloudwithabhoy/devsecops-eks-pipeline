variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type = string
  default = "10.0.0.0/16"
}

variable "project_name" {
  description = "Name of the project - used for tagging resources"
  type = string
}

variable "environment" {
  description = "Environment name (dev,staging,prod)"
  type = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets(one per AZ)"
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]

}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ) — EKS nodes run here"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}