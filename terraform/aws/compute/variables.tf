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

# AWS EC2 Key Pair에 등록할 로컬 공개키 경로다.
# 개인키가 아니라 .pub 공개키 파일만 읽는다.
variable "ssh_public_key_path" {
  description = "Local path to the SSH public key registered as an EC2 key pair"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# Control Plane과 Worker의 EC2 인스턴스 타입
variable "control_plane_instance_type" {
  description = "EC2 instance type for the control-plane node"
  type        = string
  default     = "m7i-flex.large"
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}

# 생성할 AWS Worker 수다. 현재 단일 Worker PoC 기본값은 1이다.
variable "worker_count" {
  description = "Number of AWS Kubernetes worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.worker_count >= 1 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be an integer greater than or equal to 1."
  }
}

# Control Plane과 Worker의 암호화된 gp3 Root EBS 크기
variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "root_volume_size must be at least 20 GiB."
  }
}

# AWS Service Worker Node에 Instance Profile을 붙일지 결정한다. Self-managed
# Kubernetes에는 EKS Pod Identity가 없고 OIDC Provider 등록은 단일 Control
# Plane에서 apiserver 플래그를 바꿔야 해 이 PoC 범위를 넘는다. 대신 Node
# Instance Profile로 Pod가 IMDS에서 임시 자격증명을 받는다.
variable "enable_worker_instance_profile" {
  description = "Whether to attach an IAM instance profile to service worker nodes"
  type        = bool
  default     = false
}
