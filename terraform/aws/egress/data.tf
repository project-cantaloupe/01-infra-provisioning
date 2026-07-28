# Network 루트 모듈이 S3에 저장한 output을 조회.
# Egress plan/apply 전에 Network state 필요.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}
