# ── 사람용 창구는 여기 없다 ─────────────────────────────────────
#
# **`userpass` 를 2026-08-11 에 지웠다.** 그 블록은 "Keycloak 이 서기
# 전까지의 임시 창구" 라고 스스로 적어 두고 있었고, 그 조건이 끝났다
# → decisions/20260811_vault-oidc-replaces-userpass.md
#
# 사람 인증은 이제 oidc.tf 하나다. **이 파일에 사람용 백엔드를 다시
# 만들지 않는다** — 임시 창구가 영구 시설로 굳는 것이 이 종류 작업의
# 흔한 결말이고, 한 번 그 결말을 피했다.
#
# ⚠️ Keycloak 이 죽으면 Vault 에 사람이 못 들어간다. **그건 폴백이
# 없다는 뜻이 아니다** — 초기 root 토큰과 recovery key 5조각이 오프라인
# 봉투에 있다. 폴백을 상시 켜진 두 번째 인증 경로로 두지 않는 것이
# 여기서의 선택이다 → references/20260801_infra-05-vault-ops.md
#
# ── 기계용 창구 ─────────────────────────────────────────────────
#
# AppRole 이 값 둘로 나뉘어 있는 것은 **배달 경로를 가를 수 있어서**다.
# role_id 는 비밀이 아니라 코드나 CI 설정에 적어도 되고, secret_id 만 비밀로
# 다룬다. 한쪽이 새어도 그것만으로는 열리지 않는다.
resource "vault_auth_backend" "approle" {
  type        = "approle"
  description = "Machine auth for Terraform and Ansible runs"
}

resource "vault_approle_auth_backend_role" "terraform_onp" {
  backend        = vault_auth_backend.approle.path
  role_name      = "terraform-onp"
  token_policies = [vault_policy.terraform_onp.name]

  token_ttl     = var.approle_token_ttl_seconds
  token_max_ttl = var.approle_token_ttl_seconds * 2

  # secret_id 를 여러 번 쓸 수 있게 둔다. 0 은 무제한이다.
  # 1회용으로 묶으면 apply 를 한 번 실패할 때마다 사람이 재발급해야 한다.
  # 대신 수명을 짧게 둔다.
  secret_id_num_uses = 0
  secret_id_ttl      = 86400
}

resource "vault_approle_auth_backend_role" "ansible_onp" {
  backend        = vault_auth_backend.approle.path
  role_name      = "ansible-onp"
  token_policies = [vault_policy.ansible_onp.name]

  token_ttl     = var.approle_token_ttl_seconds
  token_max_ttl = var.approle_token_ttl_seconds * 2

  secret_id_num_uses = 0
  secret_id_ttl      = 86400
}

# ── secret_id 를 만들지 않는다 ──────────────────────────────────
#
# vault_approle_auth_backend_role_secret_id 리소스가 있지만 쓰지 않는다.
# **그 값이 tfstate 에 평문으로 들어가서 정책 스택이 시크릿 저장소가 된다** —
# 이 태스크가 없애려는 문제를 여기서 재발명하는 셈이다.
#
# 사람이 발급한다:
#   vault write -f auth/approle/role/terraform-onp/secret-id
#   vault write -f auth/approle/role/ansible-onp/secret-id
#
# secret_id_ttl 이 24시간이라 발급은 반복 작업이 된다. 자동화가 필요해지면
# CI 가 자기 secret_id 를 받는 경로(response wrapping)를 따로 만든다.

resource "vault_approle_auth_backend_role" "eso_harbor" {
  backend        = vault_auth_backend.approle.path
  role_name      = "eso-harbor"
  token_policies = [vault_policy.eso_harbor.name]

  token_ttl     = var.approle_token_ttl_seconds
  token_max_ttl = var.approle_token_ttl_seconds * 2

  # ESO 가 상시 구동되며 시크릿을 갱신해야 하므로 secret_id 만료를 두지 않는다.
  # (자동 갱신 파이프라인이 아직 없다)
  secret_id_num_uses = 0
  secret_id_ttl      = 0
}
