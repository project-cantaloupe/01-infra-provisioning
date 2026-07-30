# 상태를 로컬에 두지 않는다.
terraform {
  backend "s3" {
    bucket  = "cantaloupe-tfstate"
    key     = "gcp/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    # 세 스택이 같은 버킷을 쓴다. 키는 갈라져 있어 스택 간 충돌은 없지만
    # 같은 스택을 두 사람이 동시에 만지는 것은 락으로만 막힌다.
    use_lockfile = true
  }
}
