# Karpenter와 Golden Image 빌드 기반 자원을 관리하는 Terraform 루트다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.55.0"
    }
  }
}
