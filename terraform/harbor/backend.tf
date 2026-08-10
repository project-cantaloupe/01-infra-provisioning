terraform {
  backend "s3" {
    bucket = "cntlp-aws-tfstate"
    key    = "harbor/terraform.tfstate"
    region = "ap-northeast-2"

    encrypt = true
    # ⚠️ **`encrypt = true` 만으로는 SSE-S3 다.** 전용 키를 명시해야
    # 이 프로젝트의 제약을 만족한다 — apply 는 어느 쪽이든 성공하므로
    # 빠뜨려도 아무도 모른다
    # → decisions/20260731_tfstate-bucket-and-encryption.md
    kms_key_id = "alias/cntlp-aws-tfstate"

    use_lockfile = true
  }
}
