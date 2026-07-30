locals {
  # AWS 네이티브 자원 이름의 공통 접두사: cntlp-aws
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  # Vault 노드 이름. EC2 Name 태그이자 Ansible이 붙을 대상 이름이다.
  vault_name = "${local.name_prefix}-vault-01"

  # 모든 AWS 자원에 Provider default_tags로 적용할 필수 태그다.
  default_tags = {
    org           = local.org_token
    owner         = var.owner
    "cost-center" = var.cost_center
    "managed-by"  = "terraform"
    "data-class"  = var.data_class
    # Vault는 클러스터보다 먼저 서고 나중까지 남는다. EICE와 달리 한시적이 아니다.
    lifecycle = "permanent"
    platform  = local.platform
  }
}
