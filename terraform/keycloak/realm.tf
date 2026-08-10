# ── realm 은 하나다 ────────────────────────────────────────────
#
# `master` 는 Keycloak 자신을 관리하는 realm 이라 사람 계정을 넣지 않는다.
# master 사용자는 **모든 realm 을 관리할 수 있어서**, 거기에 팀원을 넣으면
# "Grafana 만 보는 사람"이 realm 을 지울 수 있는 계정을 갖게 된다.
#
# realm 을 여러 개(예: dev/prod)로 나누지 않는 이유는 **사람이 같아서**다.
# realm 경계는 신원 경계지 환경 경계가 아니다. 환경은 클라이언트와 RBAC 로
# 가른다.
resource "keycloak_realm" "cantaloupe" {
  realm        = local.realm_name
  enabled      = true
  display_name = "Cantaloupe"

  # ⚠️ **`all` 이어야 한다.** 기본값 `external` 은 사설 대역에서 오는
  # 요청에 평문 HTTP 를 허용한다. 이 클러스터는 전부 tailnet(100.64/10)
  # 이라 Keycloak 이 보기에 **모든 요청이 external 이 아니다.**
  # 즉 기본값이면 사실상 HTTPS 강제가 꺼진 realm 이 된다.
  ssl_required = "all"

  # ── 가입 경로를 전부 닫는다 ─────────────────────────────────
  #
  # 계정은 사람이 만든다. 이 realm 은 클러스터 접근을 가르는 곳이라
  # 자가 가입은 곧 무단 접근 신청 창구다.
  registration_allowed = false
  # 메일 서버가 없다. `true` 로 두면 사용자가 "비밀번호 재설정"을 눌렀을 때
  # 메일이 안 가고 **성공한 것처럼 보이는 화면만 뜬다.**
  reset_password_allowed = false
  verify_email           = false

  # username 으로만 로그인한다. 이메일 로그인을 켜면 이메일이 사실상
  # 두 번째 식별자가 되는데, `preferred_username` 클레임은 그대로라
  # **K8s RBAC 주체와 로그인 이름이 달라 보인다.**
  login_with_email_allowed = false
  duplicate_emails_allowed = false

  # ── 세션과 토큰 ─────────────────────────────────────────────
  #
  # ⚠️ **`access_token_lifespan` 은 kubectl 체감 지연이 아니다.**
  # kubectl 의 oidc authenticator 는 만료 전에 refresh_token 으로 조용히
  # 갱신한다. 짧게 잡는 값은 "권한을 뺏은 뒤 실제로 막힐 때까지의 시간"이다.
  # 그룹에서 사람을 빼도 최대 이 시간만큼은 기존 토큰이 먹는다.
  access_token_lifespan = "5m"

  # 자리를 비웠을 때 다시 로그인해야 하는 시점.
  sso_session_idle_timeout = "8h"
  # 계속 쓰고 있어도 강제로 끊는 상한. 근무일 하나를 넘긴다.
  sso_session_max_lifespan = "12h"

  # refresh_token 을 재사용하면 새 것을 안 준다. 탈취된 refresh_token 이
  # 원래 주인과 동시에 쓰이면 그 시점에 세션이 깨진다 — 탈취 탐지가 된다.
  refresh_token_max_reuse = 0

  # ── 방어 ────────────────────────────────────────────────────
  security_defenses {
    # ⚠️ **`permanent_lockout = false` 다.** true 로 두면 무차별 대입
    # 시도만으로 **관리자 계정을 영구히 잠글 수 있다.** 지금 계정이
    # 사실상 하나라 그건 자기 자신에 대한 DoS 다. 지수 백오프로 늦추되
    # 스스로 풀리게 둔다.
    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 10
      wait_increment_seconds           = 60
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
    }

    headers {
      # 관리 콘솔을 iframe 에 못 넣게 한다 — clickjacking 방어.
      x_frame_options = "SAMEORIGIN"
      # `frame-src 'self'` 가 없으면 Keycloak 자신의 iframe 기반
      # 세션 확인(`check-session-iframe`)이 깨진다.
      content_security_policy             = "frame-src 'self'; frame-ancestors 'self'; object-src 'none';"
      content_security_policy_report_only = ""
      x_content_type_options              = "nosniff"
      x_robots_tag                        = "none"
      x_xss_protection                    = "1; mode=block"
      strict_transport_security           = "max-age=31536000; includeSubDomains"
    }
  }
}
