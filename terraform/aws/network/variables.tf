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

variable "availability_zone" {
  description = "Single Availability Zone used by the PoC"
  type        = string
  default     = "ap-northeast-2a"

  validation {
    condition     = can(regex("^${var.aws_region}[a-z]$", var.availability_zone))
    error_message = "availability_zone must be a standard Availability Zone in aws_region."
  }
}

variable "owner" {
  description = "Owning team tag in lowercase kebab-case"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.owner))
    error_message = "owner must use lowercase kebab-case, for example team-platform."
  }
}

variable "cost_center" {
  description = "Cost center tag in lowercase kebab-case"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.cost_center))
    error_message = "cost_center must use lowercase kebab-case, for example cc-1042."
  }
}

variable "data_class" {
  description = "Data classification tag in lowercase kebab-case"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.data_class))
    error_message = "data_class must use lowercase kebab-case, for example user-audio."
  }
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
  description = "One public subnet CIDR block for the single-AZ PoC"
  type        = list(string)
  default     = ["10.20.0.0/24"]

  validation {
    condition = (
      length(var.public_subnet_cidrs) == 1
      && alltrue([
        for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))
      ])
    )
    error_message = "public_subnet_cidrs must contain exactly one valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR block for Kubernetes nodes in the single-AZ PoC"
  type        = list(string)
  default     = ["10.20.10.0/24"]

  validation {
    condition = (
      length(var.private_subnet_cidrs) == 1
      && alltrue([
        for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr))
      ])
    )
    error_message = "private_subnet_cidrs must contain exactly one valid IPv4 CIDR block."
  }
}

variable "management_cidrs" {
  description = "VPN or other routed CIDRs allowed to access SSH and the Kubernetes API"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.management_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "management_cidrs must contain valid IPv4 CIDR blocks."
  }
}

variable "remote_cluster_cidrs" {
  description = "Routed GCP and on-prem node, Pod, or VPN CIDRs allowed to communicate with AWS Kubernetes nodes"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.remote_cluster_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "remote_cluster_cidrs must contain valid IPv4 CIDR blocks."
  }
}
