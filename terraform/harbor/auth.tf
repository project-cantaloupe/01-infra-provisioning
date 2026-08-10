# ── Harbor 인증을 Keycloak 으로 돌린다 ─────────────────────────
#
# 시크릿은 terraform/keycloak 이 만들어 넣은 것을 읽는다. 두 스택을
# remote_state 로 묶지 않고 **Secrets Manager 를 접점으로 쓴다** — 한쪽이
# 없어도 다른 쪽이 plan 은 된다.
#
# ⚠️ 이 data source 가 읽은 값은 tfstate 에 남는다. keycloak 스택에서 이미
# 그런 상태이므로 새로 생기는 노출은 없고, 근거는 그쪽과 같다 —
# tfstate 는 전용 KMS 키로 보호된다.
data "aws_secretsmanager_secret_version" "harbor_oidc" {
  secret_id = "cntlp/oidc/harbor"
}

locals {
  oidc = jsondecode(data.aws_secretsmanager_secret_version.harbor_oidc.secret_string)
}

# ── ⚠️ 이 리소스는 되돌리기가 비싸다 ──────────────────────────
#
# `auth_mode` 는 **admin 외 사용자가 DB 에 없을 때만** 바꿀 수 있다.
# 한 명이라도 온보딩되면 Harbor 가 전환을 거부한다. 즉 이 값은
# 실질적으로 **한 방향**이고, 되돌리려면 온보딩된 사용자를 먼저 지워야
# 한다 (그들이 만든 것도 함께).
#
# 적용 전에 확인했다 (2026-08-11): 사용자 0, 로봇 0, 프로젝트는 library 뿐.
#
#   curl -u admin:$PW $HARBOR/api/v2.0/users
#   curl -u admin:$PW $HARBOR/api/v2.0/robots
resource "harbor_config_auth" "oidc" {
  auth_mode = "oidc_auth"

  oidc_name          = "Keycloak"
  oidc_endpoint      = var.keycloak_issuer
  oidc_client_id     = local.oidc.client_id
  oidc_client_secret = local.oidc.client_secret

  # ⚠️ **`groups` 를 빼면 아래 admin_group 이 조용히 아무 일도 안 한다.**
  # 스코프에 없으면 토큰에 클레임이 안 실리고, 클레임이 없으면 Harbor 는
  # "그룹이 없는 사용자"로 읽는다 — 에러가 아니라 권한 없음으로 나타난다.
  oidc_scope = "openid,profile,email,groups"

  oidc_groups_claim = "groups"

  # 이 그룹에 있으면 Harbor 시스템 관리자가 된다.
  oidc_admin_group = var.admin_group

  # ⚠️ **기본값은 `sub` 이고 그건 UUID 다.** 그대로 두면 Harbor 사용자
  # 목록이 `f47ac10b-58cc-...` 로 채워져 사람을 못 알아본다. 되돌리려면
  # 사용자를 지워야 하므로 처음부터 맞춰야 한다.
  #
  # `preferred_username` 은 K8s RBAC 주체와 같은 값이라 감사 로그를
  # 이어붙이기도 쉽다 → Grafana 의 login_attribute_path 와 같은 선택.
  oidc_user_claim = "preferred_username"

  # 첫 로그인에 Harbor 계정을 자동으로 만든다. 그룹이 권한을 정하므로
  # 계정을 미리 만들어 둘 이유가 없다.
  oidc_auto_onboard = true

  # 공개 CA(Let's Encrypt)라 검증을 켠다. 끄는 것은 발행자를 사칭하는
  # 상대에게 토큰을 넘길 수 있다는 뜻이다.
  oidc_verify_cert = true
}
