# NAT Gateway 상태를 Network 및 Compute와 분리하여 S3에 저장.
# terraform init 전에 S3 버킷 생성 필요.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    # Egress를 독립적으로 생성·삭제하기 위한 별도 상태 경로.
    key     = "aws/egress/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # **encrypt = true 만으로는 SSE-S3(AES256) 다.** 버킷 기본 암호화가
    # aws:kms 여도 소용없다 — S3 백엔드가 PUT 마다 암호화 방식을 명시해서
    # 보내므로 명시값이 버킷 기본값을 이긴다. 이 줄이 없으면 terraform 이
    # 쓸 때마다 상태 객체가 조용히 AES256 으로 되돌아간다.
    # → docs/runbook-tfstate.md, findings/20260731_tfstate-sse-silent-downgrade.md
    kms_key_id = "alias/cntlp-aws-tfstate"
    # 동시에 같은 상태가 변경되지 않도록 S3 잠금 파일을 사용.
    use_lockfile = true
  }
}
