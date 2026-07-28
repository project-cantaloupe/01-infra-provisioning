locals {
  # AWS 네이티브 자원 이름의 공통 접두사: cntlp-aws
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  # 입력받은 Public Subnet CIDR 목록을 for_each에서 사용할 map으로 변환한다.
  # 현재는 단일 AZ PoC라 항목이 하나지만, 이름 번호는 01부터 부여한다.
  public_subnets = {
    for index, cidr in var.public_subnet_cidrs :
    tostring(index) => {
      cidr   = cidr
      az     = var.availability_zone
      number = format("%02d", index + 1)
    }
  }

  # Kubernetes 노드를 배치할 Private Subnet도 같은 방식으로 계산한다.
  private_subnets = {
    for index, cidr in var.private_subnet_cidrs :
    tostring(index) => {
      cidr   = cidr
      az     = var.availability_zone
      number = format("%02d", index + 1)
    }
  }

  # 모든 AWS 자원에 Provider default_tags로 적용할 필수 태그다.
  # Name과 role처럼 자원마다 달라지는 태그는 각 resource 블록에서 추가한다.
  default_tags = {
    org           = local.org_token
    owner         = var.owner
    "cost-center" = var.cost_center
    "managed-by"  = "terraform"
    "data-class"  = var.data_class
    lifecycle     = "permanent"
    platform      = local.platform
  }
}
