# Tailscale 구성 전 Private EC2 SSH 접속을 위한 EICE 전용 Security Group을 생성.
resource "aws_security_group" "eice" {
  count = var.enable_eice ? 1 : 0

  name        = "${local.name_prefix}-eice-sg"
  description = "Outbound SSH access from EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  # EICE에서 Kubernetes 노드가 위치한 Private Subnet의 SSH 포트만 허용.
  egress {
    description = "SSH to Kubernetes nodes in private subnets"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = {
    Name         = "${local.name_prefix}-eice-sg"
    lifecycle    = "temporary"
    "expires-on" = var.eice_expires_on
  }
}

# Public IP와 Bastion 없이 Private EC2에 접속할 EICE를 생성.
resource "aws_ec2_instance_connect_endpoint" "main" {
  count = var.enable_eice ? 1 : 0

  subnet_id          = values(aws_subnet.private)[0].id
  security_group_ids = [aws_security_group.eice[0].id]
  ip_address_type    = "ipv4"
  preserve_client_ip = false

  tags = {
    Name         = "${local.name_prefix}-eice"
    lifecycle    = "temporary"
    "expires-on" = var.eice_expires_on
  }
}
