mock_provider "aws" {}

variables {
  aws_account_id = "123456789012"
  aws_region     = "ap-northeast-2"
  owner          = "team-platform"
}

run "packer_builder_foundation" {
  command = plan

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        vpc_id             = "vpc-00000000000000000"
        private_subnet_ids = ["subnet-00000000000000000"]
      }
    }
  }

  # mock_provider는 aws_iam_policy_document의 JSON도 임의 값으로 대체하므로
  # JSON 입력을 받는 IAM Resource에는 유효한 문서를 명시한다.
  override_data {
    target = data.aws_iam_policy_document.packer_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_ssm
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  assert {
    condition = (
      aws_iam_role.packer.name == "cntlp-aws-cicd-packer"
      && aws_iam_instance_profile.packer.name == "cntlp-aws-cicd-packer"
    )
    error_message = "Packer IAM resources must follow the approved AWS naming convention."
  }

  assert {
    condition = (
      aws_security_group.packer.name == "cntlp-aws-cicd-packer-sg"
      && aws_vpc_security_group_egress_rule.packer.ip_protocol == "-1"
      && aws_vpc_security_group_egress_rule.packer.cidr_ipv4 == "0.0.0.0/0"
    )
    error_message = "The Packer builder must use its dedicated outbound-only Security Group."
  }

  assert {
    condition     = output.packer_subnet_id == "subnet-00000000000000000"
    error_message = "The Packer builder must use the existing private subnet."
  }
}

run "golden_ami_boot_test" {
  command = plan

  variables {
    enable_boot_test     = true
    boot_test_ami_name   = "cntlp-aws-cicd-k8s-worker-abcdef0"
    boot_test_expires_on = "2099-12-31"
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        vpc_id             = "vpc-00000000000000000"
        private_subnet_ids = ["subnet-00000000000000000"]
      }
    }
  }

  override_data {
    target = data.aws_ami.boot_test
    values = {
      id = "ami-00000000000000000"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_ssm
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  assert {
    condition = (
      aws_instance.boot_test[0].ami == "ami-00000000000000000"
      && aws_instance.boot_test[0].instance_type == "t3.small"
      && aws_instance.boot_test[0].associate_public_ip_address == false
    )
    error_message = "The Boot Test must use the selected Golden AMI on one private t3.small instance."
  }

  assert {
    condition = (
      aws_instance.boot_test[0].metadata_options[0].http_tokens == "required"
      && aws_instance.boot_test[0].metadata_options[0].http_put_response_hop_limit == 2
      && aws_instance.boot_test[0].root_block_device[0].encrypted == true
      && aws_instance.boot_test[0].root_block_device[0].delete_on_termination == true
    )
    error_message = "The Boot Test must require IMDSv2 and use an encrypted disposable root volume."
  }

  assert {
    condition = (
      aws_instance.boot_test[0].tags["Name"] == "cntlp-aws-cicd-worker-boot"
      && aws_instance.boot_test[0].tags["role"] == "service"
      && aws_instance.boot_test[0].tags["lifecycle"] == "temporary"
      && aws_instance.boot_test[0].tags["expires-on"] == "2099-12-31"
    )
    error_message = "The Boot Test instance must follow the naming and temporary lifecycle tag conventions."
  }
}

run "automatic_join_boot_test" {
  command = plan

  variables {
    enable_boot_test            = true
    enable_bootstrap_foundation = true
    boot_test_join_cluster      = true
    boot_test_ami_name          = "cntlp-aws-cicd-k8s-worker-abcdef0"
    boot_test_expires_on        = "2099-12-31"
    bootstrap_expires_on        = "2099-12-31"
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        vpc_id                    = "vpc-00000000000000000"
        private_subnet_ids        = ["subnet-00000000000000000"]
        cluster_security_group_id = "sg-00000000000000001"
        worker_security_group_id  = "sg-00000000000000002"
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.compute
    values = {
      outputs = {
        worker_role_name             = "cntlp-aws-worker-node"
        worker_role_arn              = "arn:aws:iam::123456789012:role/cntlp-aws-worker-node"
        worker_instance_profile_name = "cntlp-aws-worker-node"
      }
    }
  }

  override_data {
    target = data.aws_ami.boot_test
    values = {
      id = "ami-00000000000000000"
    }
  }

  override_resource {
    target          = aws_secretsmanager_secret.worker_bootstrap
    override_during = plan
    values = {
      arn  = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:cntlp-aws-cicd-worker-bootstrap-mock"
      name = "cntlp-aws-cicd-worker-bootstrap"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_ssm
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.worker_bootstrap_secret
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  assert {
    condition = (
      aws_secretsmanager_secret.worker_bootstrap[0].name == "cntlp-aws-cicd-worker-bootstrap"
      && aws_secretsmanager_secret.worker_bootstrap[0].recovery_window_in_days == 0
      && aws_secretsmanager_secret.worker_bootstrap[0].tags["lifecycle"] == "temporary"
      && aws_secretsmanager_secret.worker_bootstrap[0].tags["expires-on"] == "2099-12-31"
    )
    error_message = "The bootstrap Secret container must be temporary and follow the approved naming convention."
  }

  assert {
    condition = (
      aws_iam_role_policy.worker_bootstrap_secret[0].role == "cntlp-aws-worker-node"
      && aws_instance.boot_test[0].iam_instance_profile == "cntlp-aws-worker-node"
      && toset(aws_instance.boot_test[0].vpc_security_group_ids) == toset([
        "sg-00000000000000001",
        "sg-00000000000000002",
      ])
    )
    error_message = "The automatic join test must use the real Service Worker IAM and Security Group boundary."
  }

  assert {
    condition = (
      strcontains(aws_instance.boot_test[0].user_data, "/usr/local/sbin/cntlp-worker-bootstrap")
      && strcontains(aws_instance.boot_test[0].user_data, "cntlp-aws-wk-99")
      && !strcontains(aws_instance.boot_test[0].user_data, "tskey-")
      && length(regexall("[a-z0-9]{6}\\.[a-z0-9]{16}", aws_instance.boot_test[0].user_data)) == 0
    )
    error_message = "The automatic join user data must invoke the bootstrap runner without embedding either credential."
  }
}

run "karpenter_controller_foundation" {
  command = plan

  variables {
    enable_controller_foundation = true
  }

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        vpc_id             = "vpc-00000000000000000"
        private_subnet_ids = ["subnet-00000000000000000"]
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.compute
    values = {
      outputs = {
        worker_role_name             = "cntlp-aws-worker-node"
        worker_role_arn              = "arn:aws:iam::123456789012:role/cntlp-aws-worker-node"
        worker_instance_profile_name = "cntlp-aws-worker-node"
        control_plane_role_name      = "cntlp-aws-control-plane-node"
      }
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.packer_ssm
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.karpenter_controller
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  assert {
    condition = (
      aws_iam_role_policy.karpenter_controller[0].name == "cntlp-aws-cicd-karpenter-controller"
      && aws_iam_role_policy.karpenter_controller[0].role == "cntlp-aws-control-plane-node"
      && output.worker_instance_profile_name == "cntlp-aws-worker-node"
      && output.kubernetes_cluster_name == "cntlp-k8s"
    )
    error_message = "The Karpenter controller policy must use the existing Control Plane and Worker IAM boundaries."
  }
}
