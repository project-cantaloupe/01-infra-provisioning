# 이 디렉터리는 Network 전용 Terraform 루트 모듈이다.
# Terraform CLI와 AWS Provider의 허용 버전 범위를 여기서 제한한다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.55 계열의 패치 버전만 허용하고, 실제 선택 버전은
      # 같은 디렉터리의 .terraform.lock.hcl이 고정한다.
      version = "~> 6.55.0"
    }
  }
}
