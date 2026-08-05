# Edge 상태를 Network, Compute 상태와 분리해 NLB만 독립적으로 관리한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    key    = "aws/edge/terraform.tfstate"
    region = "ap-northeast-2"

    encrypt      = true
    use_lockfile = true
  }
}
