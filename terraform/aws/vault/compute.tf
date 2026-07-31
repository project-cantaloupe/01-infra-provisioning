# 로컬 SSH 공개키를 Vault 전용 Key Pair로 등록한다.
# 개인키는 로컬에만 남고 AWS나 Terraform state에 올라가지 않는다.
resource "aws_key_pair" "vault" {
  key_name   = "${local.name_prefix}-vault-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${local.name_prefix}-vault-key"
  }
}

# ── Security Group — 8200을 열지 않는다 ─────────────────────────
#
# **여기에 8200 ingress 규칙을 넣지 말 것.** 넣어도 아무 효과가 없고,
# 넣으면 인터넷 노출로 오해된다.
#
# Vault API는 Tailscale 터널 안으로만 들어온다. tailnet 트래픽은 WireGuard로
# 캡슐화돼 tailscale0 인터페이스에 도착하므로, Security Group이 보는 것은
# 8200/tcp가 아니라 UDP 위의 암호화된 페이로드다. 즉 8200 규칙은 걸리지 않는다.
#
# 인바운드 UDP 41641(WireGuard 직접 연결)도 열지 않는다. 없으면 Tailscale이
# DERP 릴레이로 폴백해서 동작은 하고 지연만 늘어난다. cluster Security Group도
# 같은 선택을 했으므로 맞춘다.
#
# SSH만 EICE에서 들어온다. 그게 Vault가 메시에 들어가기 전 유일한 접근 경로다.
resource "aws_security_group" "vault" {
  name        = "${local.name_prefix}-vault-sg"
  description = "Vault node; API reachable only through the Tailscale tunnel"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # EICE가 켜져 있을 때만 SSH ingress를 만든다.
  # EICE는 lifecycle=temporary 자원이다. 지운 뒤 Vault를 다시 세우려면
  # 한시적으로 다시 켜야 한다 — references/20260801_infra-05-vault-ops.md
  dynamic "ingress" {
    for_each = toset(data.aws_security_groups.eice.ids)

    content {
      description     = "SSH from EC2 Instance Connect Endpoint"
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # 아웃바운드가 살아 있어야 tailnet 조인과 KMS·S3 호출이 된다.
  # 실제 인터넷 도달 여부는 Private Route Table의 기본 경로가 결정한다 —
  # egress 스택이 그것을 만든다 (data.tf 의 check 블록 참고).
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-vault-sg"
  }
}

resource "aws_instance" "vault" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  # Control Plane·Worker와 같은 첫 번째 Private Subnet에 배치한다.
  subnet_id              = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.vault.id]
  key_name               = aws_key_pair.vault.key_name
  iam_instance_profile   = aws_iam_instance_profile.vault.name

  # 인터넷에 직접 노출하지 않는다. 아웃바운드는 NAT Gateway를 지난다.
  associate_public_ip_address = false

  # user_data는 hostname만 설정한다. Vault 설치·설정·조인은 Ansible
  # vault-server 롤이 한다 — Compute 스택의 노드와 같은 분담이다.
  #
  # **tailnet 조인도 여기서 하지 않는다.** EICE가 있어서 Ansible이 메시 밖에서
  # 붙을 수 있으므로, auth key를 user_data에 심을 이유가 없다. 심으면 그 값이
  # tfstate와 인스턴스 메타데이터에 평문으로 남는다.
  user_data = <<-EOF
    #!/bin/bash
    set -eux

    hostnamectl set-hostname ${local.vault_name}

    cat >/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg <<'CFG'
    preserve_hostname: true
    CFG
  EOF

  # user_data가 바뀌면 설정이 일부만 적용된 EC2를 남기지 않고 교체한다.
  #
  # **교체는 raft 데이터를 지운다.** 바꾸기 전에 스냅샷을 뜬다 —
  # references/20260801_infra-05-vault-ops.md 의 재생성 절차.
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  volume_tags = {
    Name = "${local.vault_name}-root"
  }

  # EC2 Metadata Service는 토큰이 필요한 IMDSv2만 허용한다.
  # 이 인스턴스의 자격증명은 unseal 키를 만질 수 있어서 SSRF로 새면 치명적이다.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # 새 Ubuntu AMI가 생겨도 기존 Vault를 자동 교체하지 않는다.
  lifecycle {
    ignore_changes = [ami]
  }

  # ── role 태그를 붙이지 않는다 ─────────────────────────────────
  #
  # **role 은 Kubernetes 노드 전용 라벨이다.** 허용값은 control-plane · service ·
  # devops · monitoring · messaging · logging 이고, Terraform 태그 → 동적
  # inventory → kubeadm join → Node 라벨까지 그대로 흘러간다.
  # Vault 는 클러스터에 조인하지 않으므로 그 파이프라인에 넣지 않는다.
  # → decisions/20260729_k8s-labeling-convention.md
  #
  # 대신 default_tags 의 component = "vault" 로 그룹이 만들어진다
  # (inventories/aws/aws_ec2.yaml 의 component keyed_group → component_vault).
  #
  # 그래도 platform=aws 는 붙는다 — 인벤토리가 그 태그로 필터하기 때문에
  # 빼면 이 노드가 인벤토리에 아예 안 나타난다. 그래서 platform_aws 그룹에는
  # 들어가고, site-prerequisites.yaml 이 !component_vault 로 빼낸다.
  # 안 빼면 K8s 노드가 아닌 곳에 containerd 와 kubeadm-common 이 깔린다.
  tags = {
    Name = local.vault_name
  }
}
