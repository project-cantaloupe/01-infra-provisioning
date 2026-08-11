# ── 사람 인증을 Keycloak 으로 옮긴다 ───────────────────────────
#
# **이 파일이 auth.tf 의 userpass 블록을 대체한다.** `CONSTRAINTS.md` 가
# "userpass 는 Keycloak 이 서기 전까지의 임시 창구이며 OIDC 전환과
# 비활성화가 후속 태스크의 완료 조건" 이라고 적어 둔 그 전환이다
# → decisions/20260731_vault-placement.md
#
# ── 왜 이제야 가능한가 ──────────────────────────────────────────
#
# 순환이 있었다. Keycloak 은 시크릿(DB 비번·admin 비번)이 필요해 Vault 를
# 보고, Vault 는 사람을 OIDC 로 인증하고 싶어 Keycloak 을 본다.
# userpass 가 그 순환을 끊는 임시 창구였다.
#
# Keycloak 이 선 지금은 방향이 하나다 — Vault → Keycloak.
# Keycloak 쪽 시크릿은 Secrets Manager 가 받았으므로 되돌아오지 않는다
# → 02-k8s-manifests platform/aws/secops/keycloak/manifests/external-secret.yaml

data "aws_secretsmanager_secret_version" "vault_oidc" {
  secret_id = "cntlp/oidc/vault"
}

locals {
  oidc = jsondecode(data.aws_secretsmanager_secret_version.vault_oidc.secret_string)

  # ── 이름을 리터럴로 고정해 순환을 끊는다 ──────────────────────
  #
  # 백엔드는 role 의 이름을 알아야 하고(`default_role`), role 은 백엔드의
  # 경로를 알아야 한다(`backend`). 서로를 참조하면 terraform 이
  # `Cycle: vault_jwt_auth_backend_role.human, vault_jwt_auth_backend.oidc`
  # 로 거절한다 — 무엇을 먼저 만들지 정할 수 없기 때문이다.
  #
  # **둘 다 아는 값을 바깥에 두면 참조가 사라진다.** 이 두 값은 어차피
  # 리소스가 만들어낸 것이 아니라 우리가 정한 이름이라 local 이 맞는 자리다.
  # 순서는 role 쪽의 `depends_on` 이 대신 보장한다.
  oidc_path      = "oidc"
  oidc_role_name = "human"
}

# ── OIDC 백엔드 ────────────────────────────────────────────────
#
# ⚠️ **path 를 `oidc` 로 둔다.** 리다이렉트 URI 에 이 이름이 박힌다 —
# `/ui/vault/auth/<path>/oidc/callback`. 바꾸면 Keycloak 클라이언트의
# 등록 주소도 같이 고쳐야 하고, 안 고치면 `invalid redirect_uri` 가 난다.
resource "vault_jwt_auth_backend" "oidc" {
  type        = "oidc"
  path        = local.oidc_path
  description = "Human auth via Keycloak (replaces userpass)"

  oidc_discovery_url = var.keycloak_issuer
  oidc_client_id     = local.oidc.client_id
  oidc_client_secret = local.oidc.client_secret

  # UI 의 로그인 화면에 기본으로 뜰 역할. 리소스가 아니라 local 을 본다 —
  # 위의 순환 설명 참고.
  default_role = local.oidc_role_name

  # ⚠️ **`oidc_discovery_ca_pem` 을 쓰지 않는다.** 발행자가 공개 CA(Let's
  # Encrypt)라 시스템 신뢰 저장소로 충분하다. 넣으면 그 루트가 바뀌는 날
  # 이 줄이 조용히 만료된다.
  #
  # ⚠️ 다만 **이 가정은 도구마다 다시 확인해야 한다.** argocd-server 는
  # 같은 발행자에 대해 자체 tls.Config 를 만들어 시스템 루트를 못 봤다
  # → findings/20260810_argocd-oidc-session-verify-rootca.md
  # Vault 는 통과하는 것을 실제 로그인으로 확인한다.

  tune {
    default_lease_ttl = "${var.token_ttl_hours}h"
    max_lease_ttl     = "${var.token_ttl_hours}h"
    token_type        = "default-service"
  }
}

# ── 역할 — 어떤 토큰을 줄지 ────────────────────────────────────
#
# ⚠️ **`user_claim` 이 감사 로그의 이름이 된다.** 기본값을 쓰면 `sub` 이고
# 그건 UUID 다. `preferred_username` 으로 두면 기존 `userpass-pneuma` 에서
# `oidc-pneuma` 로 **같은 사람으로 읽히는 이름이 이어진다** — 실계정을
# Vault 의 userpass 계정과 같은 이름으로 만든 이유가 이것이다.
resource "vault_jwt_auth_backend_role" "human" {
  # ⚠️ **리소스가 아니라 local 을 본다.** 참조로 두면 백엔드의 `default_role`
  # 과 맞물려 순환이 된다. 대신 순서를 `depends_on` 이 명시한다 — 마운트가
  # 없는데 역할을 쓰면 404 다.
  backend   = local.oidc_path
  role_name = local.oidc_role_name
  role_type = "oidc"

  depends_on = [vault_jwt_auth_backend.oidc]

  user_claim   = "preferred_username"
  groups_claim = "groups"

  allowed_redirect_uris = [
    "https://cntlp-aws-vault-01.tail270b85.ts.net:8200/ui/vault/auth/oidc/oidc/callback",
    # CLI. `vault login -method=oidc` 가 로컬에 임시 리스너를 띄운다.
    "http://localhost:8250/oidc/callback",
  ]

  oidc_scopes = ["openid", "profile", "email", "groups"]

  # ⚠️ **여기에 정책을 직접 주지 않는다.** 주면 로그인한 사람 전부가 같은
  # 권한을 받는다. 정책은 아래 identity group 이 그룹별로 붙인다.
  #
  # 그래서 이 역할 자체의 토큰 정책은 비어 있고, 실제 권한은
  # external group 의 alias 가 매칭될 때 더해진다.
  token_policies = []
  token_ttl      = var.token_ttl_hours * 3600
  token_max_ttl  = var.token_ttl_hours * 3600
}

# ── 그룹 → 정책 ────────────────────────────────────────────────
#
# **Vault 는 OIDC 그룹을 policy 에 바로 못 붙인다.** identity 시스템의
# external group 을 만들고, 그 group 에 **alias** 로 "OIDC 백엔드에서
# 이 이름으로 오는 그룹" 을 연결해야 한다. 두 단계다.
#
#   external group (정책을 갖는다)  ←alias─  "platform-admin" (토큰의 클레임)
#
# ⚠️ **alias 이름이 클레임 값과 정확히 같아야 한다.** 우리 매퍼는
# `full_path = false` 라 `platform-admin` 으로 온다. `/platform-admin`
# 으로 적으면 매칭이 안 되고, **에러 없이 정책이 안 붙는다** —
# 로그인은 성공하고 권한만 없는 형태다.
resource "vault_identity_group" "platform_admin" {
  name     = "platform-admin"
  type     = "external"
  policies = [vault_policy.human.name]
}

resource "vault_identity_group_alias" "platform_admin" {
  name           = "platform-admin"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.platform_admin.id
}

# secops 도 같은 정책을 받는다. 시크릿을 다루는 것이 그 영역의 일이다.
#
# ⚠️ **`apps`·`devops`·`finops` 는 여기 없다.** 없으면 로그인은 되고
# 권한은 0 이다 — Vault 는 그것을 거부가 아니라 "아무것도 못 하는 토큰"
# 으로 표현한다. 필요해질 때 정책을 먼저 만들고 여기에 더한다.
resource "vault_identity_group" "secops" {
  name     = "secops"
  type     = "external"
  policies = [vault_policy.human.name]
}

resource "vault_identity_group_alias" "secops" {
  name           = "secops"
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.secops.id
}
