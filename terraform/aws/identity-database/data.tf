# Network 루트 모듈이 S3에 저장한 output을 읽는다.
# `database` 스택과 같은 Private Subnet 을 쓴다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}
