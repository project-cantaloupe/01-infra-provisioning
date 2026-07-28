# NAT Gateway 상태를 Network 및 Compute와 분리하여 S3에 저장.
# terraform init 전에 S3 버킷 생성 필요.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # Egress를 독립적으로 생성·삭제하기 위한 별도 상태 경로.
    key     = "aws/egress/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # 동시에 같은 상태가 변경되지 않도록 S3 잠금 파일을 사용.
    use_lockfile = true
  }
}
