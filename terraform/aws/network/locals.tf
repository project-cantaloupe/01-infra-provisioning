locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  public_subnets = {
    for index, cidr in var.public_subnet_cidrs :
    tostring(index) => {
      cidr   = cidr
      az     = var.availability_zone
      number = format("%02d", index + 1)
    }
  }

  private_subnets = {
    for index, cidr in var.private_subnet_cidrs :
    tostring(index) => {
      cidr   = cidr
      az     = var.availability_zone
      number = format("%02d", index + 1)
    }
  }

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
