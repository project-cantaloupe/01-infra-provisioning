locals {
  # AWS 네이티브 자원 이름은 cntlp-aws-<component>[-<qualifier>] 규칙을 따른다.
  org_token     = "cntlp"
  platform      = "aws"
  component     = "api"
  name_prefix   = "${local.org_token}-${local.platform}-${local.component}"
  database_port = 5432

  # 모든 AWS 자원에 Provider default_tags로 적용할 필수 태그다.
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
