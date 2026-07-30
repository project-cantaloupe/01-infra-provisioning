output "nat_gateway_id" {
  description = "Public NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IPv4 address used for private subnet egress"
  value       = aws_eip.nat.public_ip
}

output "private_default_route_id" {
  description = "Private route table default IPv4 route ID"
  value       = aws_route.private_default_ipv4.id
}
