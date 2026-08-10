# 이 디렉터리는 Vault **내부 설정** 전용 루트 모듈이다.
# AWS 자원을 만들지 않는다 — 그건 terraform/aws/vault 가 한다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    aws = {
      # OIDC 클라이언트 시크릿을 Secrets Manager 에서 읽는다 (oidc.tf).
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    vault = {
      source = "hashicorp/vault"
      # 5.10 계열의 패치 버전만 허용한다. 실제 선택 버전은
      # 같은 디렉터리의 .terraform.lock.hcl 이 고정한다.
      # (provider 버전은 Vault 서버 버전과 무관하다 — 서버는 2.0.x 다)
      version = "~> 5.10.0"
    }
  }
}
