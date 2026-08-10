# ── 계정은 코드에, 비밀번호는 코드 밖에 ────────────────────────
#
# **terraform 이 소유하는 것은 "누가 있고 어느 그룹인가"까지다.**
# 비밀번호는 사람이 따로 넣는다.
#
# 가르는 기준이 "비밀이냐"가 아니라 **"무엇이 접근을 구속하느냐"**다.
# 접근을 정하는 것은 비밀번호가 아니라 **그룹 소속**이다 — 비밀번호를
# 아는 사람도 `platform-admin` 이 아니면 클러스터를 못 만진다. 그래서
# 그룹은 코드에 있어야 하고 리뷰를 거쳐야 한다.
#
# ⚠️ **`initial_password` 블록을 쓰지 않는다.** 편하지만 비밀번호가
# **tfstate 에 평문으로 남는다.** S3 가 KMS 로 암호화해도 `terraform show`
# 를 할 수 있는 사람은 전부 본다
# → decisions/20260731_secret-access-no-fallback.md
#      decisions/20260810_keycloak-realm-as-code.md
resource "keycloak_user" "platform_admin" {
  realm_id = keycloak_realm.cantaloupe.id
  username = var.platform_admin_username
  enabled  = true

  email      = var.platform_admin_email
  first_name = var.platform_admin_first_name
  last_name  = var.platform_admin_last_name

  # 메일 서버가 없어서 검증 메일을 못 보낸다. `false` 로 두면 계정에
  # `VERIFY_EMAIL` 필수 작업이 붙어 로그인이 막힌다. 이 계정을 만드는
  # 사람이 곧 주소의 주인이라 검증할 상대가 없다.
  email_verified = true

  # ⚠️ **`required_actions` 를 선언하지 않는다.** `["UPDATE_PASSWORD"]`
  # 를 넣으면 첫 로그인 강제 변경이 되지만, 사용자가 그걸 끝내면
  # Keycloak 이 목록을 비우고 **terraform 은 그것을 드리프트로 보고
  # 다음 apply 마다 다시 붙인다.** 매번 비밀번호를 바꾸게 되는 것이다.
  #
  # 첫 비밀번호를 임시로 넣으면 Keycloak 이 알아서 `UPDATE_PASSWORD` 를
  # 붙인다. 선언하지 않는 편이 의도대로 동작한다.
}

# ── 그룹 소속은 배타적으로 소유한다 ────────────────────────────
#
# `exhaustive = true` 가 기본이고 그대로 둔다. 콘솔에서 손으로 그룹을
# 더해도 다음 apply 가 **되돌린다.**
#
# 불편해 보이지만 이게 목적이다 — 권한이 늘어나는 경로가 PR 하나뿐이면
# "누가 언제 왜 이 권한을 얻었나"에 git 이 답한다. 콘솔에서 조용히 늘어난
# 권한은 아무도 안 본다.
resource "keycloak_user_groups" "platform_admin" {
  realm_id = keycloak_realm.cantaloupe.id
  user_id  = keycloak_user.platform_admin.id

  # 지금은 전권 하나뿐이다. 나머지 넷은 RBAC 이 실제로 붙은 뒤
  # 필요해지면 넣는다 — 지금 다 넣으면 **어느 그룹 때문에 권한이
  # 붙었는지 구분이 안 된다.**
  group_ids = [
    keycloak_group.area["platform-admin"].id,
  ]
}
