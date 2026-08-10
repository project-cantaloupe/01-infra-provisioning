# Keycloak 설정 상태를 S3에 저장한다.
# 버킷은 terraform init 전에 있어야 한다 → references/20260801_infra-06-tfstate.md
#
# **이 상태에 사람의 비밀번호가 들어가지 않는다.** realm·그룹·클라이언트
# 구조까지만 소유하고, 사용자 계정과 비밀번호는 사람이 콘솔·CLI 로 만든다.
# 클라이언트 시크릿은 예외라서 clients.tf 를 쓸 때 다시 판단한다.
terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    key    = "keycloak/terraform.tfstate"
    region = "ap-northeast-2"

    encrypt = true
    # ⚠️ **`encrypt = true` 만 두면 SSE-S3(AES256) 다.** 버킷 기본 암호화가
    # aws:kms 여도 소용없다 — S3 백엔드가 PUT 마다 암호화 방식을 명시해서
    # 보내고, 명시값이 버킷 기본값을 이긴다. 이 줄이 없으면 상태 객체가
    # 쓸 때마다 조용히 AES256 으로 되돌아간다. 실패가 아니라 강등이라
    # 알아채기 어렵다 → findings/20260731_tfstate-sse-silent-downgrade.md
    kms_key_id = "alias/cntlp-aws-tfstate"

    # 같은 상태를 둘이 동시에 바꾸지 못하게 S3 잠금 파일을 쓴다.
    use_lockfile = true
  }
}
