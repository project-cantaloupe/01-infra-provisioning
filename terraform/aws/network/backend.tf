# 상태를 로컬에 두지 않는다.
terraform {
  backend "s3" {
    bucket       = "cntlp-aws-tfstate"
    key          = "aws/network/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
