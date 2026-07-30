# 아래 output은 S3 Network state에 저장된다.
# Compute 루트 모듈은 terraform_remote_state를 통해 이 값들을 읽는다.
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# 단일 AZ PoC에서 실제 사용한 Availability Zone
output "availability_zone" {
  description = "Availability Zone used by the single-AZ PoC"
  value       = var.availability_zone
}

# 향후 Public Load Balancer나 Gateway가 사용할 Subnet 목록
output "public_subnet_ids" {
  description = "Public subnet IDs consumed by the Egress state"
  value       = values(aws_subnet.public)[*].id
}

# Control Plane과 Worker EC2가 사용할 Subnet 목록
output "private_subnet_ids" {
  description = "Private subnet IDs consumed by the Compute state"
  value       = values(aws_subnet.private)[*].id
}

# RDS DB Subnet Group이 사용할 서로 다른 AZ의 Private Subnet 목록
output "database_subnet_ids" {
  description = "Private subnet IDs in two Availability Zones consumed by the Database state"
  value       = concat(values(aws_subnet.private)[*].id, [aws_subnet.database.id])
}

# 추후 NAT/Firewall egress 경로를 추가할 때 사용할 Route Table ID
output "private_route_table_id" {
  description = "Private route table ID reserved for a future egress route"
  value       = aws_route_table.private.id
}

# 모든 Kubernetes 노드에 공통으로 연결할 Security Group
output "cluster_security_group_id" {
  description = "Shared Kubernetes node security group ID"
  value       = aws_security_group.cluster.id
}

# Control Plane에 추가 연결할 Security Group
output "control_plane_security_group_id" {
  description = "Control-plane security group ID"
  value       = aws_security_group.control_plane.id
}

# Worker에 추가 연결할 Security Group
output "worker_security_group_id" {
  description = "Worker security group ID"
  value       = aws_security_group.worker.id
}

# EICE에서 시작한 SSH만 허용하는 ingress 규칙을 다른 스택이 만들 때 필요하다.
# cluster Security Group은 이 스택 안에 있어서 직접 참조하지만, Vault처럼
# 별도 스택의 노드는 이 값을 remote_state로 읽어야 한다.
output "eice_security_group_id" {
  description = "EICE security group ID consumed by stacks that add their own SSH ingress rule"
  value       = var.enable_eice ? aws_security_group.eice[0].id : null
}

# EICE 비활성화 시 null을 반환.
output "eice_id" {
  description = "EC2 Instance Connect Endpoint ID when EICE is enabled"
  value       = var.enable_eice ? aws_ec2_instance_connect_endpoint.main[0].id : null
}
