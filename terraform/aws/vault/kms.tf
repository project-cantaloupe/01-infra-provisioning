# ── auto-unseal ─────────────────────────────────────────────────
#
# Vault는 시작할 때 sealed 상태다. unseal하지 않으면 API가 전부 503이다.
#
# 수동 unseal은 recovery key 조각을 사람이 임계값만큼 넣는 것이고,
# 그건 **재부팅마다 사람이 필요하다**는 뜻이다. EC2는 하드웨어 문제로 알아서
# 재시작되므로 그때 아무도 없으면 Vault는 조용히 죽어 있다.
#
# awskms seal은 그 열쇠를 KMS에 맡긴다. 인스턴스 프로파일이 이 키에 Decrypt
# 권한을 가져서 부팅하면 스스로 unseal한다.
#
# **이 키를 잃으면 Vault 데이터를 잃는다.** 삭제 대기 기간을 최대로 두고,
# recovery key는 오프라인에 봉인한다 — docs/05_vault-ops.md
resource "aws_kms_key" "unseal" {
  description             = "Vault auto-unseal for ${local.vault_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-vault-unseal"
  }
}

resource "aws_kms_alias" "unseal" {
  name          = "alias/${local.name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.unseal.key_id
}
