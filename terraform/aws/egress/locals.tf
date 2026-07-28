locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  # EIP와 NAT Gateway에 공통으로 적용할 비용 및 운영 태그.
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
