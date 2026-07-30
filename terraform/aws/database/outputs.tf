output "db_instance_identifier" {
  description = "RDS DB instance identifier"
  value       = aws_db_instance.api.identifier
}

output "database_name" {
  description = "Initial PostgreSQL database name"
  value       = aws_db_instance.api.db_name
}

output "database_address" {
  description = "Private RDS hostname without the port"
  value       = aws_db_instance.api.address
}

output "database_port" {
  description = "PostgreSQL port"
  value       = aws_db_instance.api.port
}

output "master_username" {
  description = "PostgreSQL master username"
  value       = aws_db_instance.api.username
}

# ARN은 비밀번호가 아니지만 자격 증명 위치이므로 일반 출력에서 숨긴다.
output "master_user_secret_arn" {
  description = "Secrets Manager ARN containing the RDS-managed master credentials"
  value       = try(aws_db_instance.api.master_user_secret[0].secret_arn, null)
  sensitive   = true
}
