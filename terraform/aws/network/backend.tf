# Network 상태를 로컬에 두지 않고 S3에 저장한다.
# 버킷은 terraform init 전에 별도로 생성되어 있어야 한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # Compute 상태와 분리하여 Network만 독립적으로 관리한다.
    key     = "aws/network/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # **encrypt = true 만으로는 SSE-S3(AES256) 다.** 버킷 기본 암호화가
    # aws:kms 여도 소용없다 — S3 백엔드가 PUT 마다 암호화 방식을 명시해서
    # 보내므로 명시값이 버킷 기본값을 이긴다. 이 줄이 없으면 terraform 이
    # 쓸 때마다 상태 객체가 조용히 AES256 으로 되돌아간다.
    # → docs/runbook-tfstate.md, findings/20260731_tfstate-sse-silent-downgrade.md
    kms_key_id = "alias/cntlp-aws-tfstate"
    # 동시에 여러 명이 같은 상태를 변경하지 못하도록 S3 잠금 파일을 사용한다.
    use_lockfile = true
  }
}
