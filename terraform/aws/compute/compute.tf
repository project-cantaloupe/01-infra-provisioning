# 로컬 SSH 공개키를 AWS EC2 Key Pair로 등록한다.
# 개인키는 로컬에만 남고 AWS나 Terraform state에 업로드하지 않는다.
resource "aws_key_pair" "cluster" {
  key_name   = "${local.name_prefix}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${local.name_prefix}-key"
  }
}

# 단일 Kubernetes Control Plane EC2를 생성한다.
resource "aws_instance" "control_plane" {
  # 생성 시점에 조회된 최신 Ubuntu 24.04 AMI를 사용한다.
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.control_plane_instance_type
  # Network state에서 첫 번째 Private Subnet ID를 읽어 배치한다.
  subnet_id = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  # 공통 클러스터 통신 규칙과 Control Plane API 규칙을 함께 적용한다.
  vpc_security_group_ids = [
    data.terraform_remote_state.network.outputs.cluster_security_group_id,
    data.terraform_remote_state.network.outputs.control_plane_security_group_id,
  ]
  key_name = aws_key_pair.cluster.key_name
  # Control Plane은 인터넷에 직접 노출하지 않는다.
  associate_public_ip_address = false

  # 현재 AWS 상태가 false이나 코드에 없어 apply 시 기본값 true로 되돌아가는
  # 드리프트가 있었다. 누가 왜 껐는지 기록이 없어 현재 상태를 그대로 고정한다.
  #
  # Calico는 Tigera Operator 설치에 IPPool이 VXLAN=Always, IPIP=Never이므로
  # Pod 트래픽이 노드 IP로 캡슐화된다. 따라서 원칙적으로는 true여도 무방하다.
  # 다만 단일 Control Plane에서 검증 없이 바꾸면 클러스터 전체가 멈출 수 있어
  # 별도 시점에 단독으로 시험한 뒤 이 줄을 제거한다.
  source_dest_check = false

  # 현재 user_data는 hostname만 설정한다.
  # Kubernetes, containerd, kubeadm 설치는 이후 Ansible 단계에서 수행한다.
  user_data = <<-EOF
    #!/bin/bash
    set -eux

    hostnamectl set-hostname ${local.control_plane_name}

    cat >/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg <<'CFG'
    preserve_hostname: true
    CFG
  EOF

  # user_data가 바뀌면 설정이 일부만 적용된 EC2를 남기지 않고 교체한다.
  user_data_replace_on_change = true

  # EC2 Root EBS는 암호화된 gp3를 사용하고, EC2 삭제 시 함께 삭제한다.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  # EBS도 콘솔과 비용 내역에서 노드를 식별할 수 있도록 이름을 붙인다.
  volume_tags = {
    Name = "${local.control_plane_name}-root"
  }

  # EC2 Metadata Service는 토큰이 필요한 IMDSv2만 허용한다.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # AWS에 새로운 Ubuntu AMI가 생겨도 기존 Control Plane을 자동 교체하지 않는다.
  # 최초 생성 때는 최신 AMI를 사용하고, 이후 AMI 교체는 의도적으로 진행한다.
  lifecycle {
    ignore_changes = [ami]
  }

  # Ansible 동적 inventory가 role 태그로 Control Plane을 그룹화한다.
  tags = {
    Name = local.control_plane_name
    role = "control-plane"
  }
}

# worker_count만큼 Kubernetes Worker EC2를 생성한다.
resource "aws_instance" "worker" {
  count = var.worker_count

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  # Control Plane과 같은 Private Subnet에 배치한다.
  subnet_id = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  # 공통 클러스터 통신 규칙과 Worker 전용 규칙을 함께 적용한다.
  vpc_security_group_ids = [
    data.terraform_remote_state.network.outputs.cluster_security_group_id,
    data.terraform_remote_state.network.outputs.worker_security_group_id,
  ]
  key_name = aws_key_pair.cluster.key_name
  # Worker도 인터넷에 직접 노출하지 않는다.
  associate_public_ip_address = false

  # Pod가 IMDS로 임시 자격증명을 받는다. Role 권한은 각 Stack이 붙인다.
  iam_instance_profile = var.enable_worker_instance_profile ? aws_iam_instance_profile.worker[0].name : null

  # 각 Worker의 번호에 맞춰 cntlp-aws-wk-01 형태의 hostname을 설정한다.
  user_data = <<-EOF
    #!/bin/bash
    set -eux

    hostnamectl set-hostname ${local.worker_names[count.index]}

    cat >/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg <<'CFG'
    preserve_hostname: true
    CFG
  EOF

  # user_data 변경 시 해당 Worker를 교체한다.
  user_data_replace_on_change = true

  # Worker 삭제 시 Root EBS도 함께 삭제된다.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  volume_tags = {
    Name = "${local.worker_names[count.index]}-root"
  }

  # EC2 Metadata Service는 토큰이 필요한 IMDSv2만 허용한다.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # 최신 AMI 발견만으로 기존 Worker가 자동 교체되지 않게 한다.
  lifecycle {
    ignore_changes = [ami]
  }

  # Ansible 동적 inventory가 role 태그로 Worker를 그룹화한다.
  tags = {
    Name = local.worker_names[count.index]
    role = "service"
  }
}
