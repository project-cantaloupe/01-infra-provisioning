# Public NAT Gateway가 사용할 고정 Public IPv4 주소를 생성.
# Egress stack destroy 시 EIP 해제 및 Public IPv4 과금 중단.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

# Private Subnet에 IPv4 인터넷 egress를 제공하는 Zonal Public NAT Gateway를 생성.
# 단일 AZ PoC의 첫 번째 Public Subnet에 배치.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = data.terraform_remote_state.network.outputs.public_subnet_ids[0]

  tags = {
    Name = "${local.name_prefix}-nat"
  }
}

# Control Plane과 Worker의 인터넷 outbound를 NAT Gateway로 전달.
# Egress stack destroy 시 기본 Route 제거 및 VPC local Route만 유지.
resource "aws_route" "private_default_ipv4" {
  route_table_id         = data.terraform_remote_state.network.outputs.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
