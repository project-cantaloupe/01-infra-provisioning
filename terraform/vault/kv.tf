# KV v2. v1 이 아니다 — v2 는 버전 이력과 소프트 삭제가 있어서 시크릿을 잘못
# 덮었을 때 되돌릴 수 있다. 회전하다 값을 날리는 것이 이 종류 작업의 흔한 사고다.
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "cantaloupe secrets; path layout in tasks/doing/006_vault-setup.md section 2"
}

# 버전 보관 개수를 명시한다. 기본값(10)에 의존하면 나중에 바뀌었을 때 모른다.
resource "vault_kv_secret_backend_v2" "secret" {
  mount        = vault_mount.secret.path
  max_versions = 10
  cas_required = false
  # 0 = 자동 삭제하지 않는다. 초 단위 숫자다.
  # 시크릿을 시간으로 지우면 회전이 밀렸을 때 값이 사라진다.
  delete_version_after = 0
}

# ── 시크릿 값을 terraform 으로 넣지 않는다 ──────────────────────
#
# vault_kv_secret_v2 리소스가 있지만 쓰지 않는다. **그 값이 tfstate 에 평문으로
# 들어간다.** 이 태스크가 없애려는 것이 바로 그 사본이다.
#
# 값은 사람이 CLI 로 넣는다. 셸 히스토리에도 남기지 않는다 —
# `@파일` 과 `-` (stdin) 을 쓴다.
#
#   vault kv put secret/onp/proxmox   api_token=... endpoint=...
#   vault kv put secret/onp/tailscale auth_key=...
#   vault kv put secret/ssh/cntlp-public  authorized_keys=@~/.ssh/cantaloupe_ed25519.pub
#   vault kv put secret/ssh/cntlp-private private_key=@~/.ssh/cantaloupe_ed25519
#
# 절차 전문은 docs/04_secrets.md 를 본다.
#
# **공개키와 개인키가 다른 경로인 것이 정책 설계의 전제다.** KV v2 에 필드 단위
# ACL 이 없어서, 한 경로에 뭉치면 공개키를 읽는 주체가 개인키까지 읽는다.
# policies/terraform-onp.hcl 주석 참고.
