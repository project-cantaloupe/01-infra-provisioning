# ── 자격증명은 환경변수로만 받는다 ─────────────────────────────
#
# 값은 클러스터의 `harbor-system/harbor-v2-admin` 시크릿에 있다.
#
#   export HARBOR_URL="https://cntlp-onp-wk-01.tail270b85.ts.net"
#   export HARBOR_USERNAME="admin"
#   export HARBOR_PASSWORD=$(kubectl -n harbor-system get secret harbor-v2-admin \
#       -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)
#
# ⚠️ **data source 로 읽지 않는다.** terraform 이 읽은 값은 tfstate 에
# 평문으로 남는다. 환경변수로 넘긴 provider 설정은 state 에 안 들어간다
# → terraform/keycloak/provider.tf 의 같은 논지
#
# ⚠️ **admin 계정은 OIDC 전환 뒤에도 살아 있다.** Harbor 는 `auth_mode` 가
# `oidc_auth` 여도 로컬 admin 의 비밀번호 로그인을 남긴다. 그것이 이
# 전환의 폴백이고, 이 스택을 다시 돌릴 수 있는 근거이기도 하다.
provider "harbor" {}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "cantaloupe"
      ManagedBy = "terraform"
      Stack     = "harbor"
    }
  }
}
