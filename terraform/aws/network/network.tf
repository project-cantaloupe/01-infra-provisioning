# 모든 AWS 네트워크 자원의 기준이 되는 VPC다.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Public Subnet이 인터넷과 통신할 때 사용할 Internet Gateway다.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# 향후 외부 공개 Load Balancer나 Gateway를 배치할 Public Subnet이다.
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  # Subnet에 EC2를 생성해도 Public IP를 자동 할당하지 않는다.
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-subnet-public-${each.value.number}"
    tier = "public"
  }
}

# Control Plane과 Worker를 배치할 Private Subnet이다.
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-subnet-private-${each.value.number}"
    tier = "private"
  }
}

# Public Subnet의 VPC 외부 트래픽을 Internet Gateway로 보낸다.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    # VPC 내부 경로 이외의 모든 IPv4 목적지를 의미한다.
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

# 각 Public Subnet에 Public Route Table을 연결한다.
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table에는 아직 인터넷 기본 경로를 넣지 않는다.
# AWS가 자동 생성하는 VPC 내부 local 경로만 존재하며, 추후 확정된
# NAT, Firewall 또는 다른 egress 구성을 여기에 연결한다.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-private"
  }
}

# Kubernetes 노드용 Private Subnet에 Private Route Table을 연결한다.
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
