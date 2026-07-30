# Database 상태를 Network, Egress, Compute와 분리하여 S3에 저장한다.
# 버킷은 terraform init 전에 별도로 생성되어 있어야 한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # EC2를 다시 만들어도 Database 상태와 수명주기는 유지한다.
    key     = "aws/database/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # 동시에 여러 명이 같은 상태를 변경하지 못하도록 S3 잠금 파일을 사용한다.
    use_lockfile = true
  }
}
