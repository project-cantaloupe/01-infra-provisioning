resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-sg-cluster"
  description = "Shared traffic rules for self-managed Kubernetes nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All cluster traffic between AWS Kubernetes nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  dynamic "ingress" {
    for_each = length(var.remote_cluster_cidrs) == 0 ? [] : [var.remote_cluster_cidrs]

    content {
      description = "Cluster traffic from routed GCP and on-prem networks"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ingress.value
    }
  }

  dynamic "ingress" {
    for_each = length(var.management_cidrs) == 0 ? [] : [var.management_cidrs]

    content {
      description = "SSH from routed management networks"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ingress.value
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-cluster"
  }
}

resource "aws_security_group" "control_plane" {
  name        = "${local.name_prefix}-cp-sg"
  description = "Access rules specific to the Kubernetes control plane"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = length(var.management_cidrs) == 0 ? [] : [var.management_cidrs]

    content {
      description = "Kubernetes API from routed management networks"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = ingress.value
    }
  }

  tags = {
    Name = "${local.name_prefix}-cp-sg"
  }
}

resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-wk-sg"
  description = "Access rules specific to Kubernetes workers"
  vpc_id      = aws_vpc.main.id

  # A public load balancer rule is added after its listener and target port
  # are agreed with the Kubernetes manifests owner.
  tags = {
    Name = "${local.name_prefix}-wk-sg"
  }
}
