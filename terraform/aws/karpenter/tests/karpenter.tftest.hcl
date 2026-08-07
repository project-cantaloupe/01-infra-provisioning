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
