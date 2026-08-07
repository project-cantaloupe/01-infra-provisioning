# Karpenter 기반 자원을 기존 Network, Compute 상태와 분리한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    key    = "aws/karpenter/terraform.tfstate"
    region = "ap-northeast-2"

    encrypt      = true
    use_lockfile = true
  }
}
