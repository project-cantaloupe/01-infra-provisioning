# 인증 정보는 코드에 넣지 않는다.
# AWS CLI profile, 환경 변수, IAM Role 등 AWS 기본 자격 증명 체인을 사용한다.
provider "aws" {
  region = var.aws_region
  # 로그인한 계정과 입력한 계정 ID가 다르면 배포를 중단한다.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.default_tags
  }
}
