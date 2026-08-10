# ── 사람용 창구 ─────────────────────────────────────────────────
#
# **임시 시설이다.** CONSTRAINTS.md 는 "UI 인증은 메시 안쪽 Keycloak SSO" 라고
# 정해뒀는데(decisions/20260728_network-connectivity-and-access) Vault 가
# Keycloak 보다 먼저 서기 때문에 생긴 공백을 메운다.
#
# Keycloak 이 서면 OIDC 로 갈아타고 **이 블록을 지운다.** 그것이 후속 태스크의
# 완료 조건이다 — 임시 시설이 영구 시설로 굳는 것이 이 종류 작업의 흔한 결말이다.
resource "vault_auth_backend" "userpass" {
  type        = "userpass"
  description = "Transitional human auth; remove after Keycloak OIDC lands"

  tune {
    default_lease_ttl = "${var.token_ttl_hours}h"
    max_lease_ttl     = "${var.token_ttl_hours}h"
    token_type        = "default-service"
  }
}

# ── 비밀번호를 terraform 이 정하지 않는다 ───────────────────────
#
# vault_generic_endpoint 로 사용자를 만들 수 있지만 그러면 비밀번호가 tfstate 에
# 평문으로 남는다. 사람이 CLI 로 만든다 — `password=-` 가 stdin 에서 읽어
# 셸 히스토리에도 남지 않는다.
#
#   vault write auth/userpass/users/pneuma password=- policies=pneuma
#
# 정책 이름은 var.human_username 과 같다 (policies.tf).

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
