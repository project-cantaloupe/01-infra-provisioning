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

output "audio_oidc" {
  description = "오디오 Web 빌드와 API 런타임에 넣는 공개 OIDC 설정"
  value = {
    issuer_url               = "https://auth.echoprism.cloud/realms/${keycloak_realm.cantaloupe.realm}"
    web_client_id            = keycloak_openid_client.audio_web.client_id
    api_audience             = keycloak_openid_client.audio_api.client_id
    redirect_uri             = "https://audio.echoprism.cloud/auth/callback"
    post_logout_redirect_uri = "https://audio.echoprism.cloud/"
  }
}
