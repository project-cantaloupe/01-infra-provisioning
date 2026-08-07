# Golden Image Builder를 기존 VPC의 Private Subnet에 배치한다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}
