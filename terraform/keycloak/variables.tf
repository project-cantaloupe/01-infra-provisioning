# ⚠️ **세 값이 전부 필수다.** Keycloak 24+ 는 **선언적 사용자 프로필**을
# 기본으로 켜고, 그 기본 프로필이 `email`·`firstName`·`lastName` 을
# 필수로 둔다. 비면 계정에 `VERIFY_PROFILE` 필수 작업이 자동으로 붙어
# **로그인이 막힌다.**
#
# 막히는 방식이 고약하다 — 토큰 요청이 이렇게 거절된다.
#
#   {"error":"invalid_grant","error_description":"Account is not fully set up"}
#
# 문구가 비밀번호 쪽을 의심하게 만드는데 원인은 프로필이다
# → findings/20260810_admin-cli-lightweight-access-token.md 「곁가지」

variable "platform_admin_username" {
  description = "전권 계정의 username. **K8s RBAC 주체 이름이 여기서 나온다** — oidc:<이 값>"
  type        = string

  validation {
    # 소문자·숫자·하이픈만. 대문자나 점이 들어가면 RBAC 매니페스트를
    # 손으로 쓸 때 틀리기 쉽고, 틀려도 에러가 아니라 **권한이 조용히
    # 안 붙는** 형태로 나타난다.
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.platform_admin_username))
    error_message = "username 은 소문자·숫자·하이픈만 쓴다."
  }
}

variable "platform_admin_email" {
  description = "전권 계정의 이메일. 선언적 사용자 프로필이 필수로 요구한다"
  type        = string
}

variable "platform_admin_first_name" {
  description = "전권 계정의 이름"
  type        = string
}

variable "platform_admin_last_name" {
  description = "전권 계정의 성"
  type        = string
}
