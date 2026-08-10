output "auth_mode" {
  description = "적용된 인증 모드. oidc_auth 여야 한다"
  value       = harbor_config_auth.oidc.auth_mode
}

output "admin_group" {
  description = "Harbor 시스템 관리자로 승격되는 Keycloak 그룹"
  value       = harbor_config_auth.oidc.oidc_admin_group
}
