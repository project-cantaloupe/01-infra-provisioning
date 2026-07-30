# 잘못된 AWS 계정에 배포하지 않도록 실제 계정 ID를 필수로 받는다.
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

# 비용 및 자원 관리에 사용하는 필수 태그 값
variable "owner" {
  description = "Owning team tag in lowercase kebab-case"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.owner))
    error_message = "owner must use lowercase kebab-case, for example team-audio."
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

# 서울 리전에서 실제 제공되는 PostgreSQL 버전을 명시적으로 고정한다.
variable "postgres_engine_version" {
  description = "RDS PostgreSQL engine version"
  type        = string
  default     = "18.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.postgres_engine_version))
    error_message = "postgres_engine_version must use major.minor format, for example 18.3."
  }
}

variable "db_instance_class" {
  description = "RDS DB instance class"
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.db_instance_class))
    error_message = "db_instance_class must be a valid RDS instance class, for example db.t4g.micro."
  }
}

variable "allocated_storage" {
  description = "Allocated gp3 storage in GiB"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GiB for this PostgreSQL gp3 configuration."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name"
  type        = string
  default     = "audio"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits, or underscores."
  }
}

variable "master_username" {
  description = "PostgreSQL master username; the password is managed by RDS in Secrets Manager"
  type        = string
  default     = "cntlpadmin"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain only letters, digits, or underscores."
  }
}

variable "backup_retention_period" {
  description = "Automated backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

# Compute를 지우거나 실수로 Database destroy를 실행해도 DB가 바로 삭제되지 않게 한다.
variable "deletion_protection" {
  description = "Whether RDS deletion protection is enabled"
  type        = bool
  default     = true
}

# 의도적으로 DB를 삭제할 때는 기본적으로 최종 Snapshot을 남긴다.
variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when deleting the DB instance"
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Identifier used for the final snapshot when skip_final_snapshot is false"
  type        = string
  default     = "cntlp-aws-api-db-final"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.final_snapshot_identifier))
    error_message = "final_snapshot_identifier must use lowercase letters, digits, and hyphens."
  }
}
