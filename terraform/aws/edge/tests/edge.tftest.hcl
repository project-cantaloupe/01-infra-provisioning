mock_provider "aws" {}

variables {
  aws_account_id        = "123456789012"
  aws_region            = "ap-northeast-2"
  owner                 = "team-platform"
  data_class            = "user-audio"
  allowed_ingress_cidrs = ["203.0.113.10/32"]
}

run "nlb_to_istio_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        vpc_id                   = "vpc-00000000000000000"
        public_subnet_ids        = ["subnet-00000000000000000"]
        worker_security_group_id = "sg-00000000000000000"
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.compute
    values = {
      outputs = {
        worker_node_metadata = [
          {
            name              = "cntlp-aws-wk-01"
            platform          = "aws"
            instance_id       = "i-00000000000000000"
            instance_type     = "t3.small"
            region            = "ap-northeast-2"
            availability_zone = "ap-northeast-2a"
            provider_id       = "aws:///ap-northeast-2a/i-00000000000000000"
          },
        ]
      }
    }
  }

  assert {
    condition     = aws_lb.audio.name == "cntlp-aws-audio-nlb"
    error_message = "The public NLB name must follow the cntlp AWS naming convention."
  }

  assert {
    condition = (
      aws_lb_target_group.http.port == 30080
      && aws_lb_target_group.http.health_check[0].port == "32021"
    )
    error_message = "The NLB target group must use the Istio NodePort contract."
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.http) == 1
    error_message = "Every AWS Worker must be registered in the target group."
  }

  assert {
    condition     = aws_lb_listener.http.protocol == "TCP"
    error_message = "TLS termination must remain at the Istio Gateway."
  }

  # Gateway가 443을 바인딩하지 않는 동안 NLB도 443을 열지 않는다.
  assert {
    condition     = length(aws_lb_listener.http.default_action) == 1
    error_message = "The HTTP listener must forward to exactly one target group."
  }

  # 공개 범위는 allowed_ingress_cidrs가 정한 값과 정확히 일치해야 한다.
  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.audio_nlb_http) == 1
      && aws_vpc_security_group_ingress_rule.audio_nlb_http["203.0.113.10/32"].cidr_ipv4 == "203.0.113.10/32"
    )
    error_message = "The NLB ingress rules must match allowed_ingress_cidrs exactly."
  }

  # NLB와 Worker 사이는 HTTP와 health NodePort 두 개만 열린다.
  assert {
    condition = (
      length(aws_vpc_security_group_egress_rule.audio_nlb_to_worker) == 2
      && length(aws_vpc_security_group_ingress_rule.worker_from_audio_nlb) == 2
    )
    error_message = "Only the HTTP and health NodePorts may be reachable from the NLB."
  }
}

# AUTH_MODE=development에서 전체 공개를 막는 방어선이 실제로 동작하는지 확인한다.
run "rejects_open_internet_ingress" {
  command = plan

  variables {
    allowed_ingress_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_ingress_cidrs]
}

run "rejects_empty_ingress" {
  command = plan

  variables {
    allowed_ingress_cidrs = []
  }

  expect_failures = [var.allowed_ingress_cidrs]
}
