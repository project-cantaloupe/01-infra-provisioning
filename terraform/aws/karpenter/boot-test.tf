# Golden AMI가 새 EC2의 초기 부팅을 완료하는지 Karpenter 설치 전에 분리해
# 검증한다. 이 인스턴스는 Karpenter가 소유하는 Node가 아니며 테스트 후 삭제한다.
data "aws_ami" "boot_test" {
  count = var.enable_boot_test ? 1 : 0

  owners      = ["self"]
  most_recent = true

  filter {
    name   = "name"
    values = [var.boot_test_ami_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "boot_test" {
  count = var.enable_boot_test ? 1 : 0

  ami                    = data.aws_ami.boot_test[0].id
  instance_type          = "t3.small"
  subnet_id              = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.packer.id]
  iam_instance_profile   = aws_iam_instance_profile.packer.name

  associate_public_ip_address = false

  # Karpenter 자동 명명 규칙을 확정하기 전이므로 기존 Node 패턴의 99번을
  # Boot Test 전용으로 예약한다. 이 단계에서는 tailnet과 Kubernetes에 가입하지 않는다.
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    hostnamectl set-hostname cntlp-aws-wk-99

    cat >/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg <<'CFG'
    preserve_hostname: true
    CFG
  EOF

  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  tags = {
    Name         = "${local.name_prefix}-cicd-worker-boot"
    role         = "service"
    lifecycle    = "temporary"
    "expires-on" = var.boot_test_expires_on
  }

  volume_tags = merge(local.default_tags, {
    Name         = "${local.name_prefix}-cicd-worker-boot-root"
    role         = "service"
    lifecycle    = "temporary"
    "expires-on" = var.boot_test_expires_on
  })

  depends_on = [
    aws_iam_role_policy.packer_ssm,
    aws_vpc_security_group_egress_rule.packer,
  ]
}
