# 인증 정보는 AWS CLI profile, 환경 변수, IAM Role 중 하나로 전달한다.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.default_tags
  }
}
