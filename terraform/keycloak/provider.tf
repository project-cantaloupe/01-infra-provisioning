# 주소와 자격증명을 코드에 넣지 않는다. 환경 변수를 읽는다.
# terraform/vault 의 `provider "vault" {}` 와 같은 이유다
# → decisions/20260731_secret-access-no-fallback.md
#
#   export KEYCLOAK_URL="https://auth.echoprism.cloud"
#   export KEYCLOAK_CLIENT_ID="admin-cli"
#   export KEYCLOAK_REALM="master"
#   export KEYCLOAK_USER="<부트스트랩 관리자>"
#   export KEYCLOAK_PASSWORD="<비밀번호>"
#
# 값은 AWS Secrets Manager 의 `cntlp/keycloak/bootstrap-admin` 에 있다.
# **data source 로 읽지 않는 이유가 여기 있다** — terraform 의 data source
# 결과는 tfstate 에 평문으로 남는다. 환경 변수는 state 에 안 들어간다.
#
#   export KEYCLOAK_PASSWORD=$(aws secretsmanager get-secret-value \
#     --secret-id cntlp/keycloak/bootstrap-admin \
#     --query SecretString --output text | jq -r .password)
#
# ── 이 자격증명은 임시다 ────────────────────────────────────────
#
# 부트스트랩 관리자는 realm 이 서면 지운다(태스크 008). 그 뒤 이 스택은
# **service account 클라이언트**로 붙는다 — `terraform` 클라이언트에
# client_credentials 를 켜고 `realm-management` 의 필요한 role 만 준다.
# 지금 그렇게 못 하는 이유는 그 클라이언트를 만들 손이 이 스택이라서다.
#
# ⚠️ **`initial_login` 기본값이 true 다.** provider 가 plan 단계에서
# 이미 로그인을 시도하므로, Keycloak 이 안 떠 있으면 plan 부터 실패한다.
# 에러가 "리소스가 없다"가 아니라 연결 실패로 나와서 원인이 헷갈린다.
provider "keycloak" {}
