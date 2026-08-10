locals {
  realm_name = "cantaloupe"

  # ── 그룹 이름은 `area` 라벨 값과 같다 ──────────────────────────
  #
  # 네임스페이스·파드 라벨·비용 태그가 이미 이 단어들을 쓴다
  # → repos/00-cantaloupe-resources/k8s-labeling-convention.md
  #
  # **같은 단어를 쓰면 "이 그룹이 무엇을 만지나"가 라벨 하나로 답해진다.**
  # `oidc:devops` 그룹의 RBAC 범위는 `area=devops` 인 것들이다. 이름이
  # 다르면 그 사이에 사람이 외우는 매핑표가 하나 더 생긴다.
  #
  # ⚠️ **`platform-admin` 만 `area` 값에 없다.** `area` 에는 `platform` 이
  # 있지만 그건 "플랫폼 영역의 워크로드"라는 뜻이라 전권과 다르다.
  # 전권을 `platform` 이라고 부르면 스토리지 CSI 를 만지는 사람과
  # cluster-admin 이 같은 단어가 된다.
  groups = {
    "platform-admin" = "클러스터·Vault 전권. 지금은 1명"
    "apps"           = "오디오 서비스"
    "devops"         = "CI/CD — ArgoCD·Jenkins·Harbor"
    "finops"         = "비용·모니터링·거버넌스"
    "secops"         = "보안 — Vault·Keycloak·Kyverno·Falco"
  }
}
