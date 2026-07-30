# Vault 설정 상태를 S3에 저장한다.
# 버킷은 terraform init 전에 별도로 생성되어 있어야 한다.
#
# **이 상태에 시크릿 값이 들어가지 않는다.** mount·정책·role 까지만 소유하고,
# 시크릿과 secret_id 는 사람이 vault CLI 로 넣는다 — kv.tf 와 auth.tf 주석 참고.
terraform {
  backend "s3" {
    bucket       = "cntlp-aws-tfstate"
    key          = "vault/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
