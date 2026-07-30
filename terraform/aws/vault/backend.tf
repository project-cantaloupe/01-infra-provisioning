# Vault 상태를 다른 스택과 분리하여 S3에 저장한다.
# 버킷은 terraform init 전에 별도로 생성되어 있어야 한다.
#
# **이 상태에는 시크릿이 들어가지 않는다.** Vault 안의 값은 이 스택이 만들지
# 않고, KMS 키와 버킷 이름 같은 식별자만 담는다.
# 시크릿 투입은 사람이 vault CLI로 한다 — tasks/doing/006_vault-setup.md 6절.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # Vault는 클러스터보다 먼저 서고 나중까지 남는다. Compute와 생애가 달라
    # 상태를 분리한다.
    key     = "aws/vault/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # 동시에 여러 명이 같은 상태를 변경하지 못하도록 S3 잠금 파일을 사용한다.
    use_lockfile = true
  }
}
