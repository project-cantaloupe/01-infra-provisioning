# ── 권한은 그룹으로만 표현한다 ─────────────────────────────────
#
# **realm role 을 안 쓴다.** 둘 다 토큰에 실을 수 있지만, 사람이 늘 때
# 만지는 곳이 하나여야 한다. 그룹만 쓰면 "사람 → 그룹" 한 줄이고,
# 역할까지 쓰면 "사람 → 그룹 → 역할 → 시스템별 권한"이 되어 어디를
# 봐야 하는지가 매번 달라진다.
#
# 각 시스템(K8s RBAC·Vault 정책·ArgoCD·Grafana)은 **그룹 이름을 직접**
# 주체로 받는다. 매핑표가 곧 태스크 008 의 3단계 산출물이다.
#
# ⚠️ **평평하게 둔다. 중첩 그룹을 만들지 않는다.** Keycloak 의 중첩 그룹은
# 하위가 상위 권한을 상속하는데, 토큰에 실릴 때 `full_path` 설정에 따라
# `/a/b` 로 나올지 `b` 로 나올지가 달라진다. K8s RBAC 은 문자열 완전
# 일치라서, 그 차이가 곧 "권한이 조용히 안 붙는" 형태로 나타난다.
resource "keycloak_group" "area" {
  for_each = local.groups

  realm_id = keycloak_realm.cantaloupe.id
  name     = each.key

  # Keycloak 그룹에는 description 필드가 없다. 속성으로 남겨 콘솔에서
  # 보이게 한다 — 토큰에는 안 실린다(매퍼를 안 붙였으므로).
  attributes = {
    purpose = each.value
  }
}
