resource "aws_key_pair" "cluster" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${var.project_name}-key"
  }
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = aws_subnet.public["0"].id
  vpc_security_group_ids      = [aws_security_group.kubernetes_nodes.id]
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

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = local.control_plane_name
    Role = "control-plane"
  }
}

resource "aws_eip" "control_plane" {
  domain   = "vpc"
  instance = aws_instance.control_plane.id

  tags = {
    Name = "${local.control_plane_name}-eip"
  }
}

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.public[tostring(count.index % 2)].id
  vpc_security_group_ids      = [aws_security_group.kubernetes_nodes.id]
  key_name                    = aws_key_pair.cluster.key_name
  associate_public_ip_address = true

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

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = local.worker_names[count.index]
    Role = "worker"
  }
}
