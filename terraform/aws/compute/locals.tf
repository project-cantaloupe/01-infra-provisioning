locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  control_plane_name = "${local.name_prefix}-cp-01"
  worker_names = [
    for index in range(var.worker_count) :
    format("%s-wk-%02d", local.name_prefix, index + 1)
  ]

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
