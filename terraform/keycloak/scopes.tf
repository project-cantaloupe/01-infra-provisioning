# ── 그룹이 토큰에 실려야 쓸모가 있다 ───────────────────────────
#
# **Keycloak 은 기본적으로 그룹을 토큰에 안 넣는다.** 2026-08-09 에
# `admin-cli` 로 받은 토큰에 `groups` 도 `preferred_username` 도 없던 것이
# 이것 때문이다 → tasks/doing/008_identity-and-sso.md 1단계 📌
#
# 그래서 client scope 를 하나 만들고 거기에 protocol mapper 를 붙인다.
# 클라이언트마다 매퍼를 복사하지 않는 이유는 **claim 이름이 한 곳에서
# 정해져야 해서**다. ArgoCD 는 `groups` 를 보고 K8s 는 `--oidc-groups-claim`
# 으로 이름을 받는데, 클라이언트마다 다르면 그 플래그가 클라이언트마다
# 달라야 한다.
resource "keycloak_openid_client_scope" "groups" {
  realm_id = keycloak_realm.cantaloupe.id
  name     = "groups"

  description = "그룹 멤버십을 groups 클레임으로 싣는다"

  # 동의 화면을 띄우지 않는다. 전부 1st-party 클라이언트라 사용자에게
  # "이 앱이 당신의 그룹을 봐도 됩니까"를 물을 이유가 없고, 물으면
  # kubectl 같은 비대화형 흐름이 막힌다.
  consent_screen_text = ""

  # 콘솔에서 스코프 목록을 정렬할 때 쓰인다. 기능에는 영향이 없다.
  gui_order = "1"
}

# ⚠️ **이 다섯 줄이 앞으로 만들 모든 RBAC 바인딩의 문자열을 정한다.**
# K8s 의 `subjects[].name`, ArgoCD 의 `policy.csv`, Grafana 의 role mapping
# 이 전부 여기서 나오는 값과 **완전 일치**해야 한다. 나중에 바꾸면 그 전부를
# 같이 고쳐야 하고, 안 고친 곳은 에러가 아니라 **권한이 조용히 안 붙는**
# 형태로 나타난다.
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id        = keycloak_realm.cantaloupe.id
  client_scope_id = keycloak_openid_client_scope.groups.id
  name            = "groups"

  # ArgoCD 와 Grafana 가 `groups` 를 기대한다. K8s 는
  # `--oidc-groups-claim` 으로 이름을 받으니 무엇이든 되지만, **바꿀 수
  # 있는 쪽이 하나뿐이면 바꿀 수 없는 쪽에 맞춘다.**
  claim_name = "groups"

  # `false` 면 `devops`, `true` 면 `/devops` 로 실린다.
  #
  # **평평한 그룹에서 앞의 슬래시는 정보를 더하지 않는다** — 중첩이
  # 없으므로 경로가 항상 `/이름` 이다. 대신 `--oidc-groups-prefix: "oidc:"`
  # 와 합쳐질 때 `oidc:/devops` 라는 읽기 나쁜 주체 이름이 나오고,
  # RBAC 매니페스트를 손으로 쓸 때 슬래시를 빠뜨리기 쉽다.
  #
  # ⚠️ **나중에 중첩 그룹이 필요해지면 이 값을 바꿔야 하는데, 그 순간
  # 모든 바인딩이 깨진다.** 그래서 groups.tf 가 중첩을 금지한다.
  full_path = false

  # ── 어느 토큰에 실을 것인가 ─────────────────────────────────
  #
  # **kubectl 은 access_token 이 아니라 id_token 을 보낸다.** kubeconfig 의
  # `id-token` 필드가 Authorization 헤더에 실리고, API 서버는 그것을
  # 검증한다. 여기가 false 면 **로그인은 되는데 모든 요청이 403** 이 된다 —
  # 인증은 통과하고 그룹만 비어서, 원인이 인가 쪽으로 보인다.
  add_to_id_token = true

  # Vault OIDC 와 Istio `RequestAuthentication` 은 access_token 을 본다.
  # 지금 소비자가 없지만, 나중에 켜려면 realm 설정을 다시 만져야 하고
  # 그때는 이미 발급된 토큰이 돌아다닌다. 처음부터 켜 둔다.
  add_to_access_token = true

  # Grafana 는 구성에 따라 `/userinfo` 를 따로 호출한다. 왕복이 한 번
  # 늘지만 토큰 크기는 안 늘어난다.
  #
  # ⚠️ **토큰 크기는 실제 한계가 있다.** 그룹이 수십 개로 늘면 JWT 가
  # 커지고, 앞단 프록시의 헤더 크기 상한(nginx 기본 4~8KB)에 걸려
  # `431 Request Header Fields Too Large` 가 난다. 지금 그룹이 5개라
  # 여유가 크지만, 늘어날 때 여기부터 본다.
  add_to_userinfo = true
}

# ── `preferred_username` 은 여기서 만들지 않는다 ────────────────
#
# 내장 `profile` 스코프의 매퍼가 이미 낸다. 2026-08-09 에 `admin-cli`
# 토큰에서 안 보였던 것은 그 클라이언트의 스코프 구성 때문이고, 새로
# 만들 클라이언트들은 `profile` 을 기본 스코프로 받는다.
#
# **매퍼를 중복으로 만들면 안 된다** — 같은 claim 을 두 매퍼가 쓰면
# 어느 쪽이 이기는지가 순서에 달리고, 그 순서는 우리가 정할 수 없다.
#
# 실제로 실리는지는 **apply 후 토큰을 받아 확인한다.** 구성만 보고
# 넘어가지 않는다 → articles/20260807_what-does-a-green-check-prove.md

# ── 클라이언트에 붙이는 것은 clients.tf 가 한다 ─────────────────
#
# 스코프를 만들어 두는 것만으로는 아무 토큰에도 안 실린다. 클라이언트마다
# `keycloak_openid_client_default_scopes` 로 붙여야 한다.
#
# realm 기본 스코프(`keycloak_realm_default_client_scopes`)로 한 번에 다는
# 방법도 있지만 **그 리소스는 목록을 통째로 소유한다** — 내장 스코프
# (`profile`·`email`·`roles`·`web-origins`…)를 빠짐없이 나열하지 않으면
# 빠진 것이 제거된다. 얻는 것에 비해 잃을 수 있는 것이 크다.
