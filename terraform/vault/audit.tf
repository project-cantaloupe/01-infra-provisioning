# ── 감사 장치 ───────────────────────────────────────────────────
#
# **이게 없으면 누가 무엇을 꺼냈는지 알 수 없다.** 창구를 사람용·기계용으로
# 가른 이유의 절반이 여기서 실현된다 — "누가 Proxmox 토큰을 꺼냈지?" 에
# userpass-pneuma 와 approle 이 다른 줄로 남는다.
#
# 설정 파일(vault.hcl)이 아니라 API 로 켠다. **초기화 전에는 켤 수 없어서**
# ansible 롤이 할 수 없다. 그래서 이 스택이 소유한다.
#
# ⚠️ **감사 장치가 하나라도 켜져 있으면 로그를 쓸 수 없을 때 Vault 가 요청을
# 거부한다.** 디스크가 차면 Vault 가 멈춘다는 뜻이다. 의도된 동작이고 —
# 감사 없이 시크릿을 내주지 않는다 — 그래서 두 가지가 따라온다.
#
#   1. vault-server 롤이 로그 디렉터리를 만들고 logrotate 를 넣는다
#   2. 디스크 감시가 런북 항목이다 (docs/runbook-vault.md)
#
# 파일 경로를 바꾸면 롤의 logrotate 설정도 같이 바꿔야 한다. 한쪽만 바꾸면
# 로그가 무한히 자라거나 rotate 가 빈 파일을 돈다.
resource "vault_audit" "file" {
  type        = "file"
  path        = "file"
  description = "File audit device; directory and rotation owned by the vault-server Ansible role"

  options = {
    file_path = var.audit_log_path
    # logrotate 가 파일을 치운 뒤 Vault 가 새로 연다.
    # 이 값이 없으면 rotate 후 Vault 가 없어진 inode 에 계속 쓴다.
    mode = "0600"
  }
}
