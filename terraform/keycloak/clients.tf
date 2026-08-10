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

# ── Grafana — 두 번째 소비자 ───────────────────────────────────
#
# ArgoCD 다음으로 고른 이유도 **폴백**이다. 로컬 admin 계정이 남아 있어
# OIDC 를 잘못 붙여도 잠기지 않는다 → tasks/doing/014_oidc-client-rollout.md
#
# ── ⚠️ 여기서부터 confidential 이다 ────────────────────────────
#
# ArgoCD 처럼 public 으로 가고 싶었지만 **Grafana 가 허용하지 않는다.**
# `auth.generic_oauth` 는 `client_id` 와 `client_secret` 을 둘 다 필수로
# 요구하고, `use_pkce` 를 켜도 면제되지 않는다 (13.1 공식 문서 확인).
#
# 이유는 흐름이 다르기 때문이다. ArgoCD 의 PKCE 는 **브라우저가** 토큰
# 엔드포인트를 직접 부르지만, Grafana 는 **서버가** 인가 코드를 교환한다.
# 서버는 비밀을 안전하게 보관할 수 있다고 보므로 OAuth 규격상 confidential
# 이 정상이다. public 으로 만들면 Keycloak 이 시크릿 인증을 거부해
# `invalid_client` 가 난다.
#
# **PKCE 는 그래도 켠다.** 시크릿을 대체하지는 못해도 인가 코드 가로채기는
# 여전히 막는다. 둘은 배타가 아니다.
#
# 시크릿이 어디로 가는지는 secrets.tf 에 있다.
resource "keycloak_openid_client" "grafana" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = "grafana"
  name      = "Grafana"
  enabled   = true

  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  # confidential 이어도 켠다. 위 주석 참고.
  pkce_code_challenge_method = "S256"

  # ⚠️ **경로가 `/grafana/login/generic_oauth` 다.** 두 조각이 붙어 있다.
  #
  #   /grafana   tailscale serve 의 경로 + grafana.ini 의 root_url
  #   /login/generic_oauth   Grafana 가 고정으로 쓰는 콜백 경로
  #
  # 서브패스를 쓰면서 앞 조각을 빠뜨리는 것이 가장 흔한 실수다. Keycloak 은
  # `Invalid parameter: redirect_uri` 를 내는데, 화면에는 그 문구만 뜨고
  # 어느 쪽이 틀렸는지는 안 알려준다.
  valid_redirect_uris = [
    "https://cntlp-gcp-wk-01.tail270b85.ts.net/grafana/login/generic_oauth",
  ]

  valid_post_logout_redirect_uris = [
    "https://cntlp-gcp-wk-01.tail270b85.ts.net/grafana/login",
  ]

  web_origins = ["+"]
}

resource "keycloak_openid_client_default_scopes" "grafana" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.grafana.id

  # ArgoCD 와 같은 목록이다. 이 리소스가 목록을 통째로 소유하므로
  # 내장 스코프를 빠뜨리면 제거된다 — 위 argocd 쪽 주석 참고.
  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.groups.name,
  ]
}

# ── Harbor — 세 번째 소비자 ────────────────────────────────────
#
# Grafana 와 같은 이유로 confidential 이다. Harbor 코어가 서버 사이드에서
# 인가 코드를 교환한다.
#
# ⚠️ **Harbor 는 PKCE 를 쓰지 않는다.** `pkce_code_challenge_method` 를
# 걸면 Keycloak 이 `code_challenge` 없는 요청을 **거절**하고, Harbor 는
# 그것을 보내지 않으므로 로그인이 통째로 막힌다. 강제하지 않는 것과
# "PKCE 를 안 쓴다"는 다른 말이고, 여기서는 전자를 고른다 — 클라이언트가
# 못 하는 것을 서버가 요구하면 그냥 안 된다.
#
# 시크릿이 진짜 자격증명이므로 confidential 의 값을 온전히 치른다.
# 그래서 리다이렉트 주소를 정확히 하나만 등록한다.
resource "keycloak_openid_client" "harbor" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = "harbor"
  name      = "Harbor"
  enabled   = true

  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  # ⚠️ **`/c/oidc/callback` 은 Harbor 가 고정으로 쓰는 경로다.**
  # `externalURL` 이 루트라(서브패스가 아니라) 앞에 붙는 조각이 없다 —
  # Grafana 가 `/grafana/login/generic_oauth` 였던 것과 대비된다.
  valid_redirect_uris = [
    "https://cntlp-onp-wk-01.tail270b85.ts.net/c/oidc/callback",
  ]

  valid_post_logout_redirect_uris = [
    "https://cntlp-onp-wk-01.tail270b85.ts.net",
  ]

  web_origins = ["+"]
}

resource "keycloak_openid_client_default_scopes" "harbor" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.harbor.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.groups.name,
  ]
}

# ── Vault — 네 번째 소비자 ─────────────────────────────────────
#
# **이 클라이언트가 `CONSTRAINTS.md` 의 한 줄을 닫는다.** Vault UI 의
# `userpass` 는 Keycloak 이 서기 전까지의 임시 창구였고, 그 삭제가 완료
# 조건으로 적혀 있다 → decisions/20260731_vault-placement.md
#
# Grafana·Harbor 와 같은 이유로 confidential 이다 — Vault 서버가 인가
# 코드를 교환한다.
#
# ⚠️ **리다이렉트가 둘인데 성격이 다르다.**
#
#   /ui/vault/auth/oidc/oidc/callback   브라우저 UI
#   http://localhost:8250/oidc/callback CLI (`vault login -method=oidc`)
#
# CLI 쪽은 **평문 http 이고 localhost 다.** 이상해 보이지만 맞다 —
# `vault login` 이 자기 기기에 임시 리스너를 띄우고 브라우저가 거기로
# 돌아온다. 그 트래픽은 기기 밖으로 나가지 않는다. 빼면 CLI 로그인이
# `invalid redirect_uri` 로 막히고, UI 만 되는 상태가 된다.
resource "keycloak_openid_client" "vault" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = "vault"
  name      = "Vault"
  enabled   = true

  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  valid_redirect_uris = [
    "https://cntlp-aws-vault-01.tail270b85.ts.net:8200/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  valid_post_logout_redirect_uris = [
    "https://cntlp-aws-vault-01.tail270b85.ts.net:8200/ui/",
  ]

  web_origins = ["+"]
}

resource "keycloak_openid_client_default_scopes" "vault" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.vault.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.groups.name,
  ]
}

# ── Kubernetes API 서버 — 다섯 번째이자 마지막 소비자 ──────────
#
# **이것이 "클러스터 통합 로그인"의 본체다.** 그리고 폴백이 가장 얇다 —
# 다른 도구는 로컬 계정이 남아 있지만 K8s API 는 잘못되면
# break-glass kubeconfig 하나뿐이다
# → references/20260810_k8s-break-glass-kubeconfig.md
#
# ── public 으로 돌아온다 ────────────────────────────────────────
#
# Grafana·Harbor·Vault 는 confidential 이었지만 여기는 다시 public 이다.
# **토큰을 교환하는 주체가 사용자 기기의 kubectl 이기 때문**이다. CLI 에
# 심은 고정 비밀은 사용자에게 그대로 노출되므로 비밀이 아니다.
#
# 판별 기준이 매번 같다 — **누가 인가 코드를 교환하는가.**
#   브라우저·CLI  → public + PKCE
#   서버          → confidential
#
# ⚠️ **API 서버는 이 클라이언트로 토큰을 받지 않는다.** 서버는 발행자의
# 공개키로 **검증만** 한다. 그래서 서버 쪽에는 시크릿이 필요 없고,
# 이 클라이언트는 순전히 kubectl 쪽 물건이다.
resource "keycloak_openid_client" "kubernetes" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = "kubernetes"
  name      = "Kubernetes API"
  enabled   = true

  access_type = "PUBLIC"

  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  pkce_code_challenge_method = "S256"

  # kubelogin(`kubectl oidc-login`)이 로컬에 임시 리스너를 띄운다.
  # 포트가 고정이 아니라 몇 개를 등록해 둔다 — 쓰는 쪽이
  # `--oidc-redirect-url-hostname` 없이 기본값을 쓰게 하려는 것이다.
  valid_redirect_uris = [
    "http://localhost:8000",
    "http://localhost:8000/",
    "http://localhost:18000",
    "http://localhost:18000/",
  ]

  web_origins = ["+"]
}

resource "keycloak_openid_client_default_scopes" "kubernetes" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.kubernetes.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.groups.name,
  ]
}

# ── OpenSearch Dashboards — oauth2-proxy 를 통해 붙는다 ────────
#
# **클라이언트의 상대가 Dashboards 가 아니라 oauth2-proxy 다.**
# OpenSearch 의 security plugin 을 켜지 않기로 했기 때문이다
# → decisions/20260811_opensearch-sso-via-proxy.md
#
# 그래서 confidential 이다 — oauth2-proxy 가 서버 사이드에서 교환한다.
# 판별 기준은 매번 같다: 누가 인가 코드를 교환하는가.
resource "keycloak_openid_client" "opensearch" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = "opensearch-dashboards"
  name      = "OpenSearch Dashboards"
  enabled   = true

  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  implicit_flow_enabled        = false
  service_accounts_enabled     = false

  # oauth2-proxy 는 PKCE 를 지원한다(v7.4+). 시크릿과 배타가 아니다.
  pkce_code_challenge_method = "S256"

  # `/oauth2/callback` 은 oauth2-proxy 의 고정 경로다. 앞의 `/logs` 는
  # tailscale serve 의 경로이고, oauth2-proxy 에도 같은 값을
  # `--proxy-prefix` 로 알려줘야 한다 — 한쪽만 바꾸면 콜백이 어긋난다.
  valid_redirect_uris = [
    "https://cntlp-onp-wk-01.tail270b85.ts.net/logs/oauth2/callback",
  ]

  valid_post_logout_redirect_uris = [
    "https://cntlp-onp-wk-01.tail270b85.ts.net/logs",
  ]

  web_origins = ["+"]
}

resource "keycloak_openid_client_default_scopes" "opensearch" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.opensearch.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.groups.name,
  ]
}

# ── ⚠️ access_token 의 aud 는 자동으로 안 붙는다 ────────────────
#
# oauth2-proxy 가 콜백에서 이렇게 죽었다 (2026-08-11 실측).
#
#   Error creating session during OAuth2 callback: audience from claim aud
#   with value [account] does not match with any of allowed audiences
#   map[opensearch-dashboards:{}]
#
# **id_token 의 `aud` 는 client_id 로 자동 설정되지만 access_token 은
# 아니다.** Keycloak 은 access_token 의 `aud` 에 기본으로 `account` 만
# 넣는다 — 그 토큰이 원래 Keycloak 자신의 account API 를 향하기 때문이다.
#
# K8s API 서버가 `aud=kubernetes` 로 문제없이 통과한 것은 **kubectl 이
# id_token 을 보내기 때문**이다. 소비자가 어느 토큰을 읽느냐로 갈린다
# → findings/20260810_admin-cli-lightweight-access-token.md 의 같은 축
#
# 고치는 자리를 프록시가 아니라 여기로 잡았다. `--oidc-extra-audience=account`
# 로 프록시에 예외를 주면 **다른 클라이언트를 향한 토큰도 받아들이게 된다** —
# audience 검증을 하는 이유가 사라진다.
resource "keycloak_openid_audience_protocol_mapper" "opensearch" {
  realm_id  = keycloak_realm.cantaloupe.id
  client_id = keycloak_openid_client.opensearch.id
  name      = "audience"

  included_client_audience = keycloak_openid_client.opensearch.client_id

  add_to_id_token     = false # id_token 에는 이미 들어 있다
  add_to_access_token = true
}
