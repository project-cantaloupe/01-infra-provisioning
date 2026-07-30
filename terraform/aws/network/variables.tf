# 잘못된 AWS 계정에 배포하지 않도록 실제 계정 ID를 필수로 받는다.
variable "aws_account_id" {
  description = "AWS account ID allowed for this stack"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# 배포 위치 설정
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

# RDS DB Subnet Group이 최소 두 Availability Zone을 포함하도록
# Kubernetes 노드용 Subnet과 다른 AZ를 하나 더 사용한다.
variable "database_availability_zone" {
  description = "Availability Zone for the additional private subnet used by RDS"
  type        = string
  default     = "ap-northeast-2c"

  validation {
    condition     = can(regex("^${var.aws_region}[a-z]$", var.database_availability_zone))
    error_message = "database_availability_zone must be a standard Availability Zone in aws_region."
  }
}

# 비용 및 자원 관리에 사용하는 필수 태그 값
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

# AWS VPC 전체 주소 범위
# GCP, On-Prem, Kubernetes Pod/Service, VPN CIDR과 겹치면 라우팅할 수 없다.
variable "vpc_cidr" {
  description = "VPC CIDR block; it must not overlap GCP, on-prem, Pod, Service, or VPN CIDRs"
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

# 향후 인터넷 공개 Load Balancer나 Gateway를 배치할 Public Subnet
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

# Control Plane과 Worker EC2를 배치할 Private Subnet
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

# RDS는 여러 AZ의 Subnet으로 구성된 DB Subnet Group을 요구한다.
# 이 Subnet에는 Kubernetes 노드를 배치하지 않고 RDS 배치 후보로만 사용한다.
variable "database_private_subnet_cidr" {
  description = "Private subnet CIDR block in a second Availability Zone for RDS"
  type        = string
  default     = "10.20.20.0/24"

  validation {
    condition     = can(cidrnetmask(var.database_private_subnet_cidr))
    error_message = "database_private_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

# VPN이나 사내 관리망처럼 SSH 및 Kubernetes API 접근을 허용할 CIDR 목록
# 빈 배열이면 외부 관리 접근용 Security Group 규칙을 만들지 않는다.
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

# Tailscale 구성 전 EICE를 통한 Private EC2 SSH 접속 사용 여부.
variable "enable_eice" {
  description = "Whether to create an EC2 Instance Connect Endpoint for temporary SSH access"
  type        = bool
  default     = false
}

# EICE를 활성화할 때 temporary lifecycle과 함께 기록할 만료일.
variable "eice_expires_on" {
  description = "ISO 8601 expiration date required when EICE is enabled"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      !var.enable_eice
      || (
        var.eice_expires_on != null
        && can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.eice_expires_on))
      )
    )
    error_message = "eice_expires_on must use YYYY-MM-DD when enable_eice is true."
  }
}
