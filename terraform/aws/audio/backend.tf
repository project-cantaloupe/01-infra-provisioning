# Audio 상태를 Network, Compute, Database, Edge 상태와 분리해 독립적으로 관리한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    key    = "aws/audio/terraform.tfstate"
    region = "ap-northeast-2"

    encrypt      = true
    use_lockfile = true
  }
}
