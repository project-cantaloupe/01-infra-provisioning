# 이 디렉터리는 Keycloak **내부 설정** 전용 루트 모듈이다.
# 서버 자체는 ArgoCD 가 배포한다 — 02-k8s-manifests/platform/aws/secops/keycloak/
#
# terraform/vault 와 같은 갈래다. **서버와 설정을 다른 도구가 소유한다.**
# 서버는 "무엇이 떠 있나", 설정은 "그 안에 무엇이 들어 있나"라서
# 수명주기가 다르다 — 파드는 재시작해도 realm 은 그대로 있어야 한다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    keycloak = {
      # ⚠️ **`mrparkers/keycloak` 이 아니다.** 원래 커뮤니티 provider 였다가
      # Keycloak 공식 네임스페이스로 이관됐다. 예전 문서를 보고 source 를
      # 옛 주소로 적으면 다른 provider 가 받아져 state 가 갈린다.
      source = "keycloak/keycloak"
      # 실제 선택 버전은 같은 디렉터리의 .terraform.lock.hcl 이 고정한다.
      # provider 버전은 Keycloak 서버 버전과 무관하다 — 서버는 26.7.1 이다.
      version = "~> 5.0"
    }

    # Grafana 부터 confidential 클라이언트가 생겨 시크릿을 클러스터로
    # 배달해야 한다. 그 경로가 Secrets Manager 라 AWS provider 가 필요하다
    # → secrets.tf
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      # oauth2-proxy 의 쿠키 암호화 키를 만든다 (secrets.tf).
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
