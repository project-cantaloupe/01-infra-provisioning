# Keycloak(Identity) DB 상태를 다른 스택과 분리하여 S3에 저장한다.
# 버킷은 terraform init 전에 별도로 생성되어 있어야 한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # Keycloak DB 는 오디오 DB 와 상태를 분리한다. 한쪽을 destroy 해도
    # 다른 쪽 state 를 건드리지 않는다.
    key     = "aws/identity-database/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # 동시에 여러 명이 같은 상태를 변경하지 못하도록 S3 잠금 파일을 사용한다.
    use_lockfile = true
  }
}
