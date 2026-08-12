# 이 디렉터리는 Harbor **내부 설정** 전용 루트 모듈이다.
# 서버 자체는 ArgoCD 가 배포한다 — 02-k8s-manifests/applications/harbor-helm.yaml
#
# `terraform/keycloak`·`terraform/vault` 와 같은 갈래다. **서버와 설정을
# 다른 도구가 소유한다.**
#
# ── 왜 Helm values 가 아니라 여기냐 ────────────────────────────
#
# **Harbor 의 인증 설정은 차트 값이 아니라 DB 에 사는 런타임 상태다.**
# `auth_mode` 를 helm values 로 줄 방법이 없고, UI 나 API 로 바꾼 값은
# PostgreSQL 에 저장된다. 즉 그대로 두면 **매니페스트를 아무리 읽어도
# 이 클러스터가 어떻게 인증하는지 알 수 없다.**
#
# ArgoCD·Grafana 는 설정이 ConfigMap·values 라 GitOps 가 그대로 덮었지만
# Harbor 는 그 층이 없다. terraform 이 그 자리를 메운다.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.11"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
