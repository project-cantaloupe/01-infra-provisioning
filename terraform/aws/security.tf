resource "aws_security_group" "kubernetes_nodes" {
  name        = "${var.project_name}-k8s-nodes"
  description = "Security group for self-managed Kubernetes nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All cluster traffic between AWS Kubernetes nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "SSH from administrator CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_admin_cidrs
  }

  ingress {
    description = "Kubernetes API from administrator CIDRs"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.allowed_admin_cidrs
  }

  ingress {
    description = "NodePort services from administrator CIDRs"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.allowed_admin_cidrs
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k8s-nodes"
  }
}
