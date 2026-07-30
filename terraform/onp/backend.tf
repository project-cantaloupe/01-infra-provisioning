# 상태를 로컬에 두지 않는다.
terraform {
  backend "s3" {
    bucket  = "cntlp-tfstate"
    key     = "onp/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    # 락이 없으면 같은 스택을 두 사람이 동시에 apply 할 때 막을 것이 없다.
    # DynamoDB 테이블 대신 S3 네이티브 락을 쓴다 — 테이블을 누가 만드느냐는
    # 닭걀 문제가 없고 dynamodb_table 은 TF 1.11 부터 deprecated 다.
    # 요구 버전: Terraform 1.10+
    use_lockfile = true
  }
}
