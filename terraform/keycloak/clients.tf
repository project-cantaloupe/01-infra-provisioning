# ── ArgoCD — 이 realm 의 첫 소비자 ─────────────────────────────
#
# 첫 클라이언트를 ArgoCD 로 고른 이유는 **로컬 `admin` 계정이라는 폴백이
# 있어서**다. OIDC 를 잘못 붙여도 잠기지 않는다. Vault 는 `userpass` 가,
# ArgoCD 는 로컬 admin 이 남아 있지만 **K8s API 서버에는 폴백이 없다** —
# 그래서 그쪽은 break-glass 런북 뒤로 미룬다.
#
# ── ⚠️ public 클라이언트다. 쓰는 시크릿이 없다 ─────────────────
#
# `access_type = "PUBLIC"` + PKCE 를 쓴다. confidential 로 하면 그 시크릿이
# **실제 자격증명**이 되고, terraform 이 읽어 tfstate 에 남으며, 거기서
# Secrets Manager → ESO → k8s Secret 로 사본이 계속 늘어난다.
#
# **정확히 하자.** Keycloak 은 public 클라이언트에도 `client_secret` 속성을
# 만들어 두고 plan 에도 `(sensitive value)` 로 보인다. 다만 **토큰
# 엔드포인트가 public 클라이언트의 시크릿 인증을 받지 않으므로 그 값은
# 자격증명이 아니다.** 사본이 늘어날 이유도 없다. "state 에 문자열이
# 없다"가 아니라 **"그 문자열로 열 수 있는 것이 없다"** 가 이 선택의 값이다.
#
# 배달 경로가 없어서 고른 것도 아니다 — ESO 컨트롤러가 AWS 노드에 있고
# k8s Secret 은 클러스터 객체라 온프렘 ArgoCD 도 읽는다. **경로는 있는데
# 지킬 것을 만들지 않는 쪽을 골랐다.**
#
# PKCE(RFC 7636)가 시크릿을 대신하는 원리 — 브라우저가 매 로그인마다
# 난수 `code_verifier` 를 만들고 그 해시(`code_challenge`)만 먼저 보낸다.
# 인가 코드를 가로챈 공격자는 원본 난수를 모르므로 토큰으로 바꾸지 못한다.
# **고정된 비밀 대신 매번 새로 만드는 비밀**이라 저장할 것이 없다.
resource "keycloak_openid_client" "argocd" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = "argocd"
  name      = "Argo CD"
  enabled   = true

  access_type = "PUBLIC"

  standard_flow_enabled = true
  # ⚠️ **직접 접속 권한(password grant)을 끈다.** 브라우저 리다이렉트를
  # 거치지 않고 아이디·비밀번호로 토큰을 받는 흐름인데, 켜 두면 PKCE 를
  # 우회하는 문이 그대로 열려 있는 것이다. public 클라이언트에서는 특히
  # 위험하다 — 누구나 이 client_id 로 무차별 대입을 시도할 수 있다.
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  # ⚠️ **이 값이 없으면 Keycloak 이 PKCE 를 강제하지 않는다.** public
  # 클라이언트라도 code_challenge 없는 요청을 그냥 받아준다. 즉 PKCE 를
  # "쓸 수 있다"와 "안 쓰면 거절한다"는 다른 이야기다.
  pkce_code_challenge_method = "S256"

  # ── 리다이렉트 주소 ─────────────────────────────────────────
  #
  # ⚠️ **`server.rootpath: /argocd` 때문에 경로에 `/argocd` 가 앞선다.**
  # 이걸 빠뜨리면 로그인은 되는데 돌아올 때 404 가 난다 — Keycloak 쪽
  # 에러가 아니라 ArgoCD 가 그 경로를 모르는 것이라 원인이 안 보인다.
  #
  # ⚠️ **PKCE 의 콜백은 `/auth/callback` 이 아니라 `/pkce/verify` 다.**
  # 브라우저가 code_verifier 를 들고 있어야 해서 서버 콜백과 경로가 다르다.
  # 둘 다 등록해 두는 것은 PKCE 를 껐을 때도 돌게 하려는 것이다.
  #
  # ⚠️ **와일드카드(`/*`)를 쓰지 않는다.** 열린 리다이렉트가 되어
  # 인가 코드를 임의 경로로 흘려보낼 수 있다.
  valid_redirect_uris = [
    "https://cntlp-onp-wk-01.tail270b85.ts.net/argocd/pkce/verify",
    "https://cntlp-onp-wk-01.tail270b85.ts.net/argocd/auth/callback",
  ]

  # 로그아웃 후 돌아올 곳.
  valid_post_logout_redirect_uris = [
    "https://cntlp-onp-wk-01.tail270b85.ts.net/argocd",
  ]

  # **PKCE 는 브라우저가 토큰 엔드포인트를 직접 부른다.** 다른 출처로
  # 취급되면 CORS 로 막히므로 출처를 명시한다. `+` 는 "valid_redirect_uris
  # 의 출처를 그대로 쓴다"는 Keycloak 의 축약이다.
  web_origins = ["+"]

  # 로그인 화면 없이 조용히 다시 인증받는 경로. 세션이 살아 있으면
  # 토큰만 갱신된다.
  login_theme = null
}

# ── 스코프를 붙여야 클레임이 실린다 ────────────────────────────
#
# ⚠️ **scopes.tf 가 `groups` 스코프를 만든 것만으로는 아무 토큰에도 안
# 실린다.** 클라이언트마다 붙이는 이 리소스가 실제로 싣는 행위다.
#
# ⚠️ **이 리소스는 목록을 통째로 소유한다.** 내장 스코프를 빠뜨리면
# 그것이 제거된다 — `profile` 을 빼면 `preferred_username` 이 사라지고,
# 그러면 ArgoCD 가 사용자를 식별하지 못한다.
resource "keycloak_openid_client_default_scopes" "argocd" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.argocd.id

  default_scopes = [
    # 내장. 빼면 안 된다
    "profile",     # preferred_username·name
    "email",       # email
    "roles",       # realm/client role (지금 안 쓰지만 aud 계산에 관여한다)
    "web-origins", # CORS 헤더
    "acr",         # 인증 컨텍스트. 빠지면 일부 흐름에서 경고가 난다
    "basic",       # sub·auth_time 등 최소 클레임 (Keycloak 25+)
    # 우리 것
    keycloak_openid_client_scope.groups.name,
  ]
}
