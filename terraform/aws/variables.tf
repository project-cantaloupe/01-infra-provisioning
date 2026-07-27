variable "aws_account_id" {
  description = "AWS account ID allowed for this stack"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used as an AWS resource-name prefix"
  type        = string
  default     = "cantaloupe"
}

variable "vpc_cidr" {
  description = "VPC CIDR block; it must not overlap GCP, on-prem, Pod, Service, or VPN CIDRs"
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "Two public subnet CIDR blocks"
  type        = list(string)
  default = [
    "10.20.0.0/24",
    "10.20.1.0/24",
  ]

  validation {
    condition = (
      length(var.public_subnet_cidrs) == 2
      && alltrue([
        for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))
      ])
    )
    error_message = "public_subnet_cidrs must contain exactly two valid IPv4 CIDR blocks."
  }
}

variable "allowed_admin_cidrs" {
  description = "CIDRs allowed to access SSH, the Kubernetes API, and NodePort services"
  type        = list(string)

  validation {
    condition = (
      length(var.allowed_admin_cidrs) > 0
      && alltrue([
        for cidr in var.allowed_admin_cidrs : can(cidrnetmask(cidr))
      ])
    )
    error_message = "allowed_admin_cidrs must contain at least one valid IPv4 CIDR block."
  }
}

variable "ssh_public_key_path" {
  description = "Local path to the SSH public key registered as an EC2 key pair"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the control-plane node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_count" {
  description = "Number of AWS Kubernetes worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be an integer greater than or equal to 1."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}
