resource "aws_key_pair" "cluster" {
  key_name   = "${local.name_prefix}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${local.name_prefix}-key"
  }
}

resource "aws_instance" "control_plane" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.control_plane_instance_type
  subnet_id     = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = [
    data.terraform_remote_state.network.outputs.cluster_security_group_id,
    data.terraform_remote_state.network.outputs.control_plane_security_group_id,
  ]
  key_name                    = aws_key_pair.cluster.key_name
  associate_public_ip_address = false

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    hostnamectl set-hostname ${local.control_plane_name}

    cat >/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg <<'CFG'
    preserve_hostname: true
    CFG
  EOF

  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  volume_tags = {
    Name = "${local.control_plane_name}-root"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = local.control_plane_name
    role = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count = var.worker_count

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  subnet_id     = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  vpc_security_group_ids = [
    data.terraform_remote_state.network.outputs.cluster_security_group_id,
    data.terraform_remote_state.network.outputs.worker_security_group_id,
  ]
  key_name                    = aws_key_pair.cluster.key_name
  associate_public_ip_address = false

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    hostnamectl set-hostname ${local.worker_names[count.index]}

    cat >/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg <<'CFG'
    preserve_hostname: true
    CFG
  EOF

  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  volume_tags = {
    Name = "${local.worker_names[count.index]}-root"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = local.worker_names[count.index]
    role = "worker"
  }
}
