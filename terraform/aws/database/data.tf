# Network 루트 모듈이 S3에 저장한 output을 읽는다.
# Network에 Database용 두 번째 Private Subnet을 먼저 apply해야 한다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}
