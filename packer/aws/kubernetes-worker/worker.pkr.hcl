packer {
  required_version = ">= 1.14.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "= 1.1.5"
    }
  }
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile used by Packer"
  default     = "cntlp"
}

variable "aws_region" {
  type        = string
  description = "AWS region where the AMI is built"
  default     = "ap-northeast-2"
}

variable "subnet_id" {
  type        = string
  description = "Private subnet used by the temporary builder instance"
}

variable "security_group_id" {
  type        = string
  description = "Outbound-only Security Group for the temporary builder instance"
}

variable "iam_instance_profile" {
  type        = string
  description = "Instance Profile that lets the builder connect through SSM"
}

variable "owner" {
  type        = string
  description = "Team responsible for the AMI"
}

variable "build_id" {
  type        = string
  description = "Immutable lowercase build identifier such as a short Git commit SHA"
}

variable "expires_on" {
  type        = string
  description = "Expiration date for the temporary builder resources in YYYY-MM-DD format"
}

variable "ansible_playbook_command" {
  type        = string
  description = "Path to the repository Ansible executable"
  default     = "ansible/.venv/bin/ansible-playbook"
}

locals {
  ami_name     = "cntlp-aws-cicd-k8s-worker-${var.build_id}"
  builder_name = "cntlp-aws-cicd-packer-builder"

  permanent_tags = {
    Name          = local.ami_name
    org           = "cntlp"
    owner         = var.owner
    "managed-by"  = "packer"
    lifecycle     = "permanent"
    platform      = "aws"
    component     = "cicd"
    "build-id"    = var.build_id
    "k8s-version" = "v1.36.3"
  }

  temporary_tags = {
    Name         = local.builder_name
    org          = "cntlp"
    owner        = var.owner
    "managed-by" = "packer"
    lifecycle    = "temporary"
    "expires-on" = var.expires_on
    platform     = "aws"
    component    = "cicd"
  }
}

source "amazon-ebs" "kubernetes_worker" {
  profile                 = var.aws_profile
  region                  = var.aws_region
  ami_name                = local.ami_name
  ami_description         = "Cantaloupe Kubernetes worker base image for Karpenter"
  ami_virtualization_type = "hvm"
  instance_type           = "t3.small"
  subnet_id               = var.subnet_id
  security_group_id       = var.security_group_id
  iam_instance_profile    = var.iam_instance_profile

  associate_public_ip_address = false
  communicator                = "ssh"
  ssh_username                = "ubuntu"
  ssh_interface               = "session_manager"
  ssh_timeout                 = "10m"
  pause_before_ssm            = "20s"
  ssh_clear_authorized_keys   = true

  imds_support = "v2.0"
  # Builder의 temporary 태그가 결과 AMI의 permanent 태그를 덮지 않게 한다.
  skip_ami_run_tags = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  tags            = local.permanent_tags
  snapshot_tags   = local.permanent_tags
  run_tags        = local.temporary_tags
  run_volume_tags = merge(local.temporary_tags, { Name = "${local.builder_name}-root" })
}

build {
  name    = "cntlp-aws-cicd-k8s-worker"
  sources = ["source.amazon-ebs.kubernetes_worker"]

  provisioner "ansible" {
    command       = abspath(var.ansible_playbook_command)
    playbook_file = abspath("ansible/playbooks/site-golden-image.yaml")
    user          = "ubuntu"
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${abspath("ansible/ansible.cfg")}",
    ]
    extra_arguments = [
      "--extra-vars",
      "ansible_python_interpreter=/usr/bin/python3",
    ]
  }

  post-processor "manifest" {
    output     = abspath("packer/aws/kubernetes-worker/manifest.json")
    strip_path = true
  }
}
