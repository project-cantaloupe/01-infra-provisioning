variable "aws_region" {
  description = "OIDC 클라이언트 시크릿이 사는 Secrets Manager 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "keycloak_issuer" {
  description = "realm 발행자 URL. terraform/keycloak 의 issuer_url 출력과 같아야 한다"
  type        = string
  default     = "https://auth.echoprism.cloud/realms/cantaloupe"
}

variable "admin_group" {
  description = <<-EOT
    Harbor 시스템 관리자로 승격할 Keycloak 그룹.
    **이 그룹에 없는 사람은 로그인해도 아무 프로젝트를 못 본다** —
    Harbor 는 프로젝트 단위 권한이라 온보딩만으로는 권한이 안 붙는다.
  EOT
  type        = string
  default     = "platform-admin"
}
