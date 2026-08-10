# 주소와 토큰을 코드에 넣지 않는다. VAULT_ADDR / VAULT_TOKEN 을 읽는다.
#
# 이 스택은 **초기 root 토큰으로 1회 apply** 된다. Vault 를 설정하려면 Vault
# 토큰이 필요한 순환을 그렇게 끊는다. apply 후 root 토큰은 오프라인 봉투로
# 돌아가고, 이후 변경은 사람 정책을 가진 토큰으로 한다.
#
#   export VAULT_ADDR="https://cntlp-aws-vault-01.<tailnet>.ts.net:8200"
#   export VAULT_TOKEN="<초기 root 토큰>"
#
# scripts/cntlp-env.sh 가 VAULT_ADDR 을 세우고 토큰 유효성을 확인한다.
provider "vault" {}

# OIDC 클라이언트 시크릿을 읽기 위해서만 쓴다 (oidc.tf).
provider "aws" {
  region = var.aws_region
}
