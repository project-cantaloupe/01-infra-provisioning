variable "human_username" {
  description = "userpass account name for the operator; a transitional auth path until Keycloak OIDC lands"
  type        = string
  default     = "pneuma"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.human_username))
    error_message = "human_username must use lowercase kebab-case."
  }
}

# 사람 토큰의 수명. **scripts/cntlp-env.sh 의 `ssh-add -t` 와 같은 값이어야
# 한다.** 다르면 한쪽이 살아 있는데 다른 쪽이 죽어 원인을 헷갈린다 —
# "Vault 는 되는데 ssh 가 안 된다" 또는 그 반대가 된다.
variable "token_ttl_hours" {
  description = "TTL for human tokens; must match the ssh-agent lifetime in scripts/cntlp-env.sh"
  type        = number
  default     = 8

  validation {
    condition     = var.token_ttl_hours >= 1 && var.token_ttl_hours <= 24
    error_message = "token_ttl_hours must be between 1 and 24."
  }
}

# AppRole 토큰 수명. terraform plan/apply 또는 ansible 실행 한 번에 넉넉하다.
# 갱신하지 않는다 — 실행이 끝나면 토큰도 죽는 것이 맞다.
variable "approle_token_ttl_seconds" {
  description = "TTL for AppRole tokens used by Terraform and Ansible runs"
  type        = number
  default     = 3600
}

variable "audit_log_path" {
  description = "File audit device path; the vault-server role creates and rotates this directory"
  type        = string
  default     = "/var/log/vault/audit.log"
}

# ── Keycloak OIDC 전환 (oidc.tf) ───────────────────────────────

variable "keycloak_issuer" {
  description = <<-EOT
    realm 발행자 URL. terraform/keycloak 의 issuer_url 출력과 같아야 한다.
    **한 번 정하면 바꾸기 비싸다** — 모든 클라이언트 설정에 박힌다.
  EOT
  type        = string
  default     = "https://auth.echoprism.cloud/realms/cantaloupe"
}

variable "aws_region" {
  description = "OIDC 클라이언트 시크릿이 사는 Secrets Manager 리전"
  type        = string
  default     = "ap-northeast-2"
}
