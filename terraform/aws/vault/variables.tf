# 잘못된 AWS 계정에 배포하지 않도록 실제 계정 ID를 필수로 받는다.
variable "aws_account_id" {
  description = "AWS account ID allowed for this stack"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

# Network 상태와 같은 AWS 리전을 사용해야 한다.
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

# Network 자원과 동일하게 유지할 비용 및 자원 관리 태그 값
variable "owner" {
  description = "Owning team tag in lowercase kebab-case; it must match the Network state"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.owner))
    error_message = "owner must use lowercase kebab-case, for example team-platform."
  }
}

variable "data_class" {
  description = "Data classification tag in lowercase kebab-case; it must match the Network state"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.data_class))
    error_message = "data_class must use lowercase kebab-case, for example user-audio."
  }
}

# Vault EC2에 등록할 로컬 공개키 경로다. 개인키가 아니라 .pub 만 읽는다.
#
# Compute 스택이 만드는 cntlp-aws-key 를 재사용하지 않는다. Vault는 클러스터보다
# 먼저 서므로 Compute state 가 없을 때도 단독으로 apply 돼야 한다.
# 같은 공개키를 다른 Key Pair 이름으로 두 번 등록하는 것은 AWS가 허용한다.
variable "ssh_public_key_path" {
  description = "Local path to the SSH public key registered as the Vault EC2 key pair"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# Vault는 CPU를 거의 쓰지 않는다. raft 단일 노드에 시크릿 수십 개면 충분하다.
# t3.micro(1GB)는 mlock 과 raft 를 같이 돌리기에 빡빡하다.
variable "instance_type" {
  description = "EC2 instance type for the Vault node"
  type        = string
  default     = "t3.small"
}

# raft 데이터가 이 볼륨에 있다. 스냅샷은 S3로 나간다.
variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 20
}

# 스냅샷 보관 기간. 시크릿을 담은 객체를 무한히 쌓지 않는다.
variable "snapshot_retention_days" {
  description = "Days to retain Vault raft snapshots in S3"
  type        = number
  default     = 90

  validation {
    condition     = var.snapshot_retention_days >= 7
    error_message = "snapshot_retention_days must be at least 7 so a weekly restore point survives."
  }
}

# KMS 키 삭제 대기 기간. **이 키를 잃으면 Vault 데이터를 잃는다.**
# AWS가 허용하는 최대치인 30일을 기본값으로 둔다.
variable "kms_deletion_window_days" {
  description = "Waiting period before the unseal KMS key is deleted"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

# EICE Security Group 이름. Network 스택이 "${name_prefix}-eice-sg" 로 만든다
# (terraform/aws/network/eice.tf). 이름으로 찾는 이유는 data.tf 주석에 있다.
#
# 못 찾으면 SSH ingress 규칙이 만들어지지 않는다 — apply 는 성공하고 접속만
# 안 된다. EICE 가 꺼져 있을 때는 그게 맞는 동작이고, 켜져 있는데 이름이
# 다르면 조용히 틀린다. 이름을 바꿀 일이 생기면 여기도 바꾼다.
variable "eice_security_group_name" {
  description = "EICE security group name created by the Network stack"
  type        = string
  default     = "cntlp-aws-eice-sg"
}
