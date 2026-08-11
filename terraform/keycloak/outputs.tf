# 이 값들은 다음 단계에서 다른 곳에 그대로 박힌다.
# 손으로 옮겨 적다 틀리면 "로그인은 되는데 토큰이 거절되는" 형태로 나타난다
# → findings/20260808_oidc-issuer-implies-port-443.md

output "issuer_url" {
  description = "K8s API 서버의 --oidc-issuer-url 과 각 클라이언트 설정에 들어간다"
  # provider 가 읽은 KEYCLOAK_URL 을 되쓰지 않고 realm 이름으로 조립한다.
  # 환경 변수에 슬래시가 붙어 있어도 결과가 흔들리지 않게 한다.
  value = "https://auth.echoprism.cloud/realms/${keycloak_realm.cantaloupe.realm}"
}

output "discovery_url" {
  description = "착지 확인용. curl 로 iss 가 issuer_url 과 같은지 본다"
  value       = "https://auth.echoprism.cloud/realms/${keycloak_realm.cantaloupe.realm}/.well-known/openid-configuration"
}

output "groups" {
  description = "RBAC·정책의 주체로 그대로 쓰는 이름들"
  value       = sort(keys(local.groups))
}
