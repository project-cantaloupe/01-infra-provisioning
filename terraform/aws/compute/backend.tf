# EC2 상태를 Network와 분리하여 S3에 저장한다.
# 버킷은 terraform init 전에 별도로 생성되어 있어야 한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # Network 상태와 분리하므로 EC2만 독립적으로 생성·삭제할 수 있다.
    key     = "aws/compute/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # 동시에 여러 명이 같은 상태를 변경하지 못하도록 S3 잠금 파일을 사용한다.
    use_lockfile = true
  }
}
