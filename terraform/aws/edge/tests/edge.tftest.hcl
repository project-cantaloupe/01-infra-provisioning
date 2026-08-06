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

# 인증서만 발급되고 A 레코드가 없으면 그 이름으로 접속할 수 없다.
# check 블록은 경고에 그치므로 변수 검증으로 apply를 막는다.
run "rejects_tls_without_dns_record" {
  command = plan

  variables {
    enable_tls        = true
    route53_zone_id   = "Z06068852958FIGZLVHZO"
    public_host       = "audio.echoprism.cloud"
    create_dns_record = false
  }

  expect_failures = [var.enable_tls]
}

# TLS를 켰을 때 443이 실제로 열리는지 확인한다. Gateway가 443을 바인딩하지
# 않으므로 NLB가 TLS를 종료하고 평문 HTTP NodePort로 넘겨야 한다.
run "tls_opens_https_on_the_same_target_group" {
  command = plan

  variables {
    enable_tls        = true
    route53_zone_id   = "Z06068852958FIGZLVHZO"
    public_host       = "audio.echoprism.cloud"
    create_dns_record = true
  }

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
    condition = (
      aws_lb_listener.https[0].protocol == "TLS"
      && aws_lb_listener.https[0].port == 443
    )
    error_message = "Enabling TLS must create a TLS listener on 443."
  }

  # Target Group ARN은 apply 전에 알 수 없어 여기서 비교할 수 없다. 443이
  # 80과 같은 Target Group을 쓰는지는 plan 출력에서 확인한다.
  assert {
    condition     = aws_acm_certificate.audio[0].domain_name == "audio.echoprism.cloud"
    error_message = "The certificate must be issued for the configured public host."
  }

  # 공개 범위는 80과 443이 같아야 한다. 한쪽만 넓어지면 통제가 새어나간다.
  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.audio_nlb_https) == 1
      && length(aws_vpc_security_group_ingress_rule.audio_nlb_http) == 1
    )
    error_message = "HTTPS ingress must follow the same allowed_ingress_cidrs as HTTP."
  }
}

# TLS를 끄면 443은 어디에도 남지 않아야 한다.
run "tls_disabled_leaves_no_https_surface" {
  command = plan

  variables {
    enable_tls        = false
    create_dns_record = false
    route53_zone_id   = null
    public_host       = null
  }

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
        worker_node_metadata = []
      }
    }
  }

  assert {
    condition = (
      length(aws_lb_listener.https) == 0
      && length(aws_acm_certificate.audio) == 0
      && length(aws_vpc_security_group_ingress_rule.audio_nlb_https) == 0
    )
    error_message = "Disabling TLS must remove the listener, certificate, and 443 ingress."
  }
}
