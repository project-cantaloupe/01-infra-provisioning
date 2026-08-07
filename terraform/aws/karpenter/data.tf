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

# Cluster에 자동 가입하는 Boot Test에서 실제 Service Worker와 같은 IAM
# Instance Profile을 사용한다. 기본 Golden AMI 부팅 검증에는 이 state를 읽지 않는다.
data "terraform_remote_state" "compute" {
  count   = local.needs_compute_state ? 1 : 0
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/compute/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}
