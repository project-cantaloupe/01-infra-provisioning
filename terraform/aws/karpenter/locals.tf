locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  packer_name = "${local.name_prefix}-cicd-packer"

  default_tags = {
    org          = local.org_token
    owner        = var.owner
    "managed-by" = "terraform"
    lifecycle    = "permanent"
    platform     = local.platform
    component    = "cicd"
  }
}
