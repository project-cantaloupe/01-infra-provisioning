# Control Plane과 Worker 모두에 붙는 공통 Security Group이다.
resource "aws_security_group" "cluster" {
  name        = "${local.name_prefix}-sg-cluster"
  description = "Shared traffic rules for self-managed Kubernetes nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All cluster traffic between AWS Kubernetes nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    # 같은 Security Group이 연결된 EC2끼리의 트래픽만 허용한다.
    self = true
  }

  # GCP/On-Prem 네트워크가 실제로 라우팅된 뒤 CIDR이 입력된 경우에만 생성한다.
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

  # VPN 또는 관리망 CIDR이 입력된 경우에만 SSH 규칙을 생성한다.
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

  # Security Group은 outbound를 허용하지만, 실제 인터넷 통신 가능 여부는
  # Private Route Table의 기본 경로 유무에 따라 결정된다.
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

# Control Plane에 추가로 붙는 Kubernetes API 전용 Security Group이다.
resource "aws_security_group" "control_plane" {
  name        = "${local.name_prefix}-cp-sg"
  description = "Access rules specific to the Kubernetes control plane"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = length(var.management_cidrs) == 0 ? [] : [var.management_cidrs]

    content {
      description = "Kubernetes API from routed management networks"
      # kube-apiserver 기본 포트
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

# Worker에 추가로 붙는 Security Group이다.
# 공통 클러스터 통신은 cluster Security Group에서 이미 허용한다.
resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-wk-sg"
  description = "Access rules specific to Kubernetes workers"
  vpc_id      = aws_vpc.main.id

  # Public Load Balancer의 listener와 Kubernetes Service 대상 포트가
  # 확정되면 LB에서 Worker로 들어오는 ingress 규칙을 여기에 추가한다.
  tags = {
    Name = "${local.name_prefix}-wk-sg"
  }
}
