# 상태를 로컬에 두지 않는다.
#
# 버킷과 암호화 키는 terraform 밖에서 손으로 만든다 — docs/runbook-tfstate.md
#
# 버킷 이름이 cntlp-tfstate 에서 cntlp-aws-tfstate 로 바뀌었다.
# 이유는 terraform/onp/backend.tf 의 주석에 있다 — 버킷 하나로 모은다.
#
# 마이그레이션할 것이 없다. 옛 이름 cntlp-tfstate 는 **버킷이 만들어진 적이
# 없다** — 2026-07-31 확인, NoSuchBucket. 이 스택도 onp 도 그 이름으로는
# 한 번도 init 되지 못했다. onp 가 backend_override.tf 로 로컬 상태를 쓰고
# 있던 진짜 이유가 이것이다.
terraform {
  backend "s3" {
    bucket  = "cntlp-aws-tfstate"
    key     = "gcp/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
    # **encrypt = true 만으로는 SSE-S3(AES256) 다.** 버킷 기본 암호화가
    # aws:kms 여도 소용없다 — S3 백엔드가 PUT 마다 암호화 방식을 명시해서
    # 보내므로 명시값이 버킷 기본값을 이긴다. 이 줄이 없으면 terraform 이
    # 쓸 때마다 상태 객체가 조용히 AES256 으로 되돌아간다.
    # → docs/runbook-tfstate.md, findings/20260731_tfstate-sse-silent-downgrade.md
    kms_key_id = "alias/cntlp-aws-tfstate"

    # 스택들이 같은 버킷을 쓴다. 키는 갈라져 있어 스택 간 충돌은 없지만
    # 같은 스택을 두 사람이 동시에 만지는 것은 락으로만 막힌다.
    use_lockfile = true
  }
}
