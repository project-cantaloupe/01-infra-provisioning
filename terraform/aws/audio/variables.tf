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

variable "owner" {
  description = "Owning team tag in lowercase kebab-case"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.owner))
    error_message = "owner must use lowercase kebab-case, for example team-audio."
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

variable "web_allowed_origins" {
  description = "Web origins allowed to upload to S3 and read CloudFront playback responses"
  type        = set(string)

  validation {
    condition = (
      length(var.web_allowed_origins) > 0
      && alltrue([
        for origin in var.web_allowed_origins :
        can(regex("^https?://[^/]+$", origin))
      ])
    )
    error_message = "web_allowed_origins must contain HTTP or HTTPS origins without a trailing path."
  }
}

variable "quarantine_standard_ia_transition_days" {
  description = "Days before current quarantine objects transition to S3 Standard-IA"
  type        = number
  default     = 30

  validation {
    condition     = var.quarantine_standard_ia_transition_days >= 30
    error_message = "quarantine_standard_ia_transition_days must be at least 30."
  }
}

variable "quarantine_glacier_ir_transition_days" {
  description = "Days before current quarantine objects transition to S3 Glacier Instant Retrieval"
  type        = number
  default     = 60

  validation {
    condition     = var.quarantine_glacier_ir_transition_days >= 60
    error_message = "quarantine_glacier_ir_transition_days must be at least 60."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain noncurrent S3 object versions"
  type        = number
  default     = 7

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "queue_max_receive_count" {
  description = "Number of receives before SQS moves a message to its DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.queue_max_receive_count >= 1 && var.queue_max_receive_count <= 20
    error_message = "queue_max_receive_count must be between 1 and 20."
  }
}

# CloudFront 공개키 파일만 Terraform이 읽으며 개인키 값은 state에 저장하지 않는다.
variable "enable_cloudfront" {
  description = "Whether to create private CloudFront playback delivery resources"
  type        = bool
  default     = false
}

variable "cloudfront_public_key_path" {
  description = "Path relative to this module containing the PEM-encoded CloudFront public key"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.cloudfront_public_key_path == null
      || (
        !startswith(var.cloudfront_public_key_path, "/")
        && !strcontains(var.cloudfront_public_key_path, "..")
      )
    )
    error_message = "cloudfront_public_key_path must be a relative path inside this module."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront edge location price class"
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

# Self-managed Kubernetes Service Account OIDC가 준비된 뒤 워크로드 IAM을 활성화한다.
variable "enable_workload_iam" {
  description = "Whether to create IAM roles for audio Kubernetes service accounts"
  type        = bool
  default     = false
}

variable "cluster_oidc_provider_arn" {
  description = "IAM OIDC provider ARN trusted by audio service accounts"
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_oidc_issuer_url" {
  description = "Kubernetes service account issuer URL registered in IAM"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.cluster_oidc_issuer_url == null || startswith(var.cluster_oidc_issuer_url, "https://")
    error_message = "cluster_oidc_issuer_url must start with https://."
  }
}

variable "audio_namespace" {
  description = "Kubernetes namespace containing the audio workloads"
  type        = string
  default     = "apps"
}

variable "audio_api_service_account" {
  description = "Kubernetes service account used by audio-api"
  type        = string
  default     = "audio-api"
}

variable "audio_events_service_account" {
  description = "Kubernetes service account used by audio-events"
  type        = string
  default     = "audio-events"
}

variable "audio_transcode_service_account" {
  description = "Kubernetes service account used by audio-transcode"
  type        = string
  default     = "audio-transcode"
}

check "cloudfront_public_key_is_available" {
  assert {
    condition = (
      !var.enable_cloudfront
      || (
        var.cloudfront_public_key_path != null
        && try(fileexists("${path.module}/${var.cloudfront_public_key_path}"), false)
      )
    )
    error_message = "cloudfront_public_key_path must reference an existing public key when enable_cloudfront is true."
  }
}

check "workload_iam_inputs_are_complete" {
  assert {
    condition = (
      !var.enable_workload_iam
      || (
        var.cluster_oidc_provider_arn != null
        && var.cluster_oidc_issuer_url != null
      )
    )
    error_message = "cluster_oidc_provider_arn and cluster_oidc_issuer_url are required when enable_workload_iam is true."
  }
}

check "quarantine_transitions_are_ordered" {
  assert {
    condition = (
      var.quarantine_glacier_ir_transition_days
      > var.quarantine_standard_ia_transition_days
    )
    error_message = "The Glacier Instant Retrieval transition must occur after the Standard-IA transition."
  }
}

# Workload IAM(OIDC) 대신 Node Instance Profile을 쓰는 동안, Audio 권한 합집합을
# Compute Stack의 Worker Role에 붙일지 결정한다. 권한 격리 단위가 ServiceAccount가
# 아니라 Node가 되는 한계가 있으며 Calico NetworkPolicy로 불필요한 Pod의 IMDS
# 접근을 차단해 보완한다. 운영 환경에서는 enable_workload_iam으로 전환한다.
variable "enable_node_role_policy" {
  description = "Whether to attach the union of audio workload permissions to the compute worker node role"
  type        = bool
  default     = false
}

# KEDA Operator는 AWS Control Plane Node에 고정되고 해당 Node Instance Profile의
# 단기 자격 증명으로 transcode Queue 길이만 읽는다. Self-managed Cluster이므로
# EKS Pod Identity나 장기 Access Key를 사용하지 않는다.
variable "enable_keda_controller_policy" {
  description = "Whether to allow the control plane node role to read transcode queue attributes for KEDA"
  type        = bool
  default     = false
}
