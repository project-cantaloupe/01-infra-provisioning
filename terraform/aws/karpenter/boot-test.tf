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

  ami           = data.aws_ami.boot_test[0].id
  instance_type = "t3.small"
  subnet_id     = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = var.boot_test_join_cluster ? [
    data.terraform_remote_state.network.outputs.cluster_security_group_id,
    data.terraform_remote_state.network.outputs.worker_security_group_id,
  ] : [aws_security_group.packer.id]
  iam_instance_profile = var.boot_test_join_cluster ? (
    local.worker_instance_profile_name
  ) : aws_iam_instance_profile.packer.name

  associate_public_ip_address = false

  # Secret 값은 user_data와 Terraform state에 넣지 않는다. 자동 가입을 켠 경우에도
  # Secret ARN만 전달하고, 실제 단기 자격증명은 Instance Profile로 런타임에 조회한다.
  user_data = templatefile("${path.module}/templates/boot-test-user-data.sh.tftpl", {
    aws_region        = var.aws_region
    bootstrap_enabled = var.boot_test_join_cluster
    node_name         = local.boot_test_node_name
    secret_id         = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.worker_bootstrap[0].arn : ""
  })

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
    aws_iam_role_policy.worker_bootstrap_secret,
    aws_vpc_security_group_egress_rule.packer,
  ]
}
