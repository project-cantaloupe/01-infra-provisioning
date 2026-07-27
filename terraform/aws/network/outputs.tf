output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "availability_zone" {
  description = "Availability Zone used by the single-AZ PoC"
  value       = var.availability_zone
}

output "public_subnet_ids" {
  description = "Public subnet IDs consumed by the Compute state"
  value       = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs consumed by the Compute state"
  value       = values(aws_subnet.private)[*].id
}

output "private_route_table_id" {
  description = "Private route table ID reserved for a future egress route"
  value       = aws_route_table.private.id
}

output "cluster_security_group_id" {
  description = "Shared Kubernetes node security group ID"
  value       = aws_security_group.cluster.id
}

output "control_plane_security_group_id" {
  description = "Control-plane security group ID"
  value       = aws_security_group.control_plane.id
}

output "worker_security_group_id" {
  description = "Worker security group ID"
  value       = aws_security_group.worker.id
}
