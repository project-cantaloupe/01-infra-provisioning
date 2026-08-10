output "db_instance_identifier" {
  description = "RDS DB instance identifier"
  value       = aws_db_instance.identity.identifier
}

output "database_name" {
  description = "Initial PostgreSQL database name"
  value       = aws_db_instance.identity.db_name
}

output "database_address" {
  description = "Private RDS hostname without the port"
  value       = aws_db_instance.identity.address
}

output "database_port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.identity.port
}

output "master_username" {
  description = "PostgreSQL master username"
  value       = aws_db_instance.identity.username
}

# Keycloak 에 비밀번호를 넣으려면 이 ARN 이 필요하다. 노드 인스턴스
# 프로파일에 붙일 인라인 정책이 이 값 하나로 좁혀진다 — 다른 시크릿은
# 못 읽는다. `database` 스택의 `cntlp-aws-api-database-node` 와 같은 모양이다.
output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the RDS-managed master password"
  value       = aws_db_instance.identity.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group attached to the identity database"
  value       = aws_security_group.identity_database.id
}
