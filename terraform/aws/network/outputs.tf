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
  description = "Public subnet IDs consumed by the Compute state"
  value       = values(aws_subnet.public)[*].id
}

# Control Plane과 Worker EC2가 사용할 Subnet 목록
output "private_subnet_ids" {
  description = "Private subnet IDs consumed by the Compute state"
  value       = values(aws_subnet.private)[*].id
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
