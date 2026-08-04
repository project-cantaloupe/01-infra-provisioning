mock_provider "aws" {}

run "nlb_to_istio_contract" {
  command = plan

  variables {
    aws_account_id = "123456789012"
    aws_region     = "ap-northeast-2"
    owner          = "team-platform"
    data_class     = "user-audio"
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
    condition     = aws_lb.audio.name == "cntlp-aws-audio-nlb"
    error_message = "The public NLB name must follow the cntlp AWS naming convention."
  }

  assert {
    condition = (
      aws_lb_target_group.http.port == 30080
      && aws_lb_target_group.https.port == 30443
      && aws_lb_target_group.http.health_check[0].port == "32021"
      && aws_lb_target_group.https.health_check[0].port == "32021"
    )
    error_message = "The NLB target groups must use the Istio NodePort contract."
  }

  assert {
    condition = (
      length(aws_lb_target_group_attachment.http) == 1
      && length(aws_lb_target_group_attachment.https) == 1
    )
    error_message = "Every AWS Worker must be registered in both target groups."
  }

  assert {
    condition = (
      aws_lb_listener.http.protocol == "TCP"
      && aws_lb_listener.https.protocol == "TCP"
    )
    error_message = "TLS termination must remain at the Istio Gateway."
  }
}
