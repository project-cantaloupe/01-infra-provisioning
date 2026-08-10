locals {
  # AWS 네이티브 자원 이름은 cntlp-aws-<component>[-<qualifier>] 규칙을 따른다.
  org_token     = "cntlp"
  platform      = "aws"
  component     = "identity"
  name_prefix   = "${local.org_token}-${local.platform}-${local.component}"
  database_port = 5432

  # 노드와 같은 AZ 에 둔다. AWS 워커·컨트롤플레인이 전부 여기 있어서,
  # 다른 AZ 에 두면 인증 질의마다 AZ 를 횡단한다. Single-AZ 인스턴스라
  # 어차피 AZ 하나에 사는 것이고, 그 AZ 가 죽으면 노드도 같이 죽으므로
  # 가용성 면에서 잃는 것이 없다.
  database_availability_zone = "ap-northeast-2a"

  default_tags = {
    org          = local.org_token
    owner        = var.owner
    "managed-by" = "terraform"
    "data-class" = var.data_class
    lifecycle    = "permanent"
    platform     = local.platform
    component    = local.component
  }
}
