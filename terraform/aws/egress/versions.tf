# Egress 전용 Terraform 루트 모듈.
# Terraform CLI와 AWS Provider의 허용 버전 범위를 제한.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # AWS Provider 6.55 계열의 패치 버전만 허용.
      # 실제 선택 버전은 .terraform.lock.hcl로 고정.
      version = "~> 6.55.0"
    }
  }
}
