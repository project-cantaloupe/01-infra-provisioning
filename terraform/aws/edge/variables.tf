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
    error_message = "owner must use lowercase kebab-case, for example team-platform."
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

# Terraform Edge와 Istio Gateway Service가 공유하는 고정 NodePort 계약이다.
variable "audio_ingress_http_node_port" {
  description = "NodePort used by the Istio ingress gateway HTTP listener"
  type        = number
  default     = 30080

  validation {
    condition     = var.audio_ingress_http_node_port >= 30000 && var.audio_ingress_http_node_port <= 32767
    error_message = "audio_ingress_http_node_port must be in the Kubernetes NodePort range 30000-32767."
  }
}

variable "audio_ingress_https_node_port" {
  description = "NodePort used by the Istio ingress gateway HTTPS listener"
  type        = number
  default     = 30443

  validation {
    condition     = var.audio_ingress_https_node_port >= 30000 && var.audio_ingress_https_node_port <= 32767
    error_message = "audio_ingress_https_node_port must be in the Kubernetes NodePort range 30000-32767."
  }
}

variable "audio_ingress_health_node_port" {
  description = "NodePort used by the NLB health check for the Istio ingress gateway"
  type        = number
  default     = 32021

  validation {
    condition     = var.audio_ingress_health_node_port >= 30000 && var.audio_ingress_health_node_port <= 32767
    error_message = "audio_ingress_health_node_port must be in the Kubernetes NodePort range 30000-32767."
  }
}

# PoC 삭제 시 NLB가 남지 않도록 기본값은 비활성화한다.
variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled on the NLB"
  type        = bool
  default     = false
}

# Route53 Zone과 서비스 주소가 확정되기 전에는 NLB DNS로만 검증한다.
variable "create_dns_record" {
  description = "Whether to create the public Route53 alias record"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 public hosted zone ID used by the audio service and cert-manager"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.route53_zone_id == null || can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "route53_zone_id must be a valid Route53 hosted zone ID."
  }
}

variable "public_host" {
  description = "Public DNS host for the audio service"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.public_host == null
      || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.public_host))
    )
    error_message = "public_host must be a lowercase DNS hostname."
  }
}

# Self-managed Kubernetes API의 Service Account OIDC 설정이 준비된 뒤 활성화한다.
variable "enable_cert_manager_iam" {
  description = "Whether to create the Route53 DNS-01 role for cert-manager"
  type        = bool
  default     = false
}

variable "cluster_oidc_provider_arn" {
  description = "IAM OIDC provider ARN trusted by the cert-manager service account"
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

check "dns_inputs_are_complete" {
  assert {
    condition = (
      !var.create_dns_record
      || (var.route53_zone_id != null && var.public_host != null)
    )
    error_message = "route53_zone_id and public_host are required when create_dns_record is true."
  }
}

check "audio_ingress_node_ports_are_distinct" {
  assert {
    condition = length(distinct([
      var.audio_ingress_http_node_port,
      var.audio_ingress_https_node_port,
      var.audio_ingress_health_node_port,
    ])) == 3
    error_message = "The Istio ingress HTTP, HTTPS, and health NodePorts must be distinct."
  }
}

check "cert_manager_iam_inputs_are_complete" {
  assert {
    condition = (
      !var.enable_cert_manager_iam
      || (
        var.route53_zone_id != null
        && var.cluster_oidc_provider_arn != null
        && var.cluster_oidc_issuer_url != null
      )
    )
    error_message = "route53_zone_id, cluster_oidc_provider_arn, and cluster_oidc_issuer_url are required when enable_cert_manager_iam is true."
  }
}
