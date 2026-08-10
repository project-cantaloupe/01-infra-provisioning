# 이 디렉터리는 Audio Edge 전용 Terraform 루트 모듈이다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55.0"
    }
  }
}
