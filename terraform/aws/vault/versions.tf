# 이 디렉터리는 Vault 전용 Terraform 루트 모듈이다.
# 다른 AWS 스택과 같은 버전 범위를 쓴다 — 한 스택만 다르면 실행자가
# 스택마다 terraform 을 바꿔야 한다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55.0"
    }
  }
}
