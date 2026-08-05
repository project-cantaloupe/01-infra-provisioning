mock_provider "aws" {}

run "core_audio_data_path" {
  command = plan

  variables {
    aws_account_id      = "123456789012"
    aws_region          = "ap-northeast-2"
    owner               = "team-audio"
    data_class          = "user-audio"
    web_allowed_origins = ["https://audio.example.com"]

    enable_cloudfront   = false
    enable_workload_iam = false
  }

  assert {
    condition = (
      aws_s3_bucket.quarantine.bucket == "cntlp-aws-quarantine"
      && aws_s3_bucket.transcode.bucket == "cntlp-aws-transcode"
    )
    error_message = "The two audio buckets must follow the approved names."
  }

  assert {
    condition = (
      aws_s3_bucket_versioning.quarantine.versioning_configuration[0].status == "Enabled"
      && aws_s3_bucket_versioning.transcode.versioning_configuration[0].status == "Enabled"
    )
    error_message = "Both audio buckets must retain object version IDs."
  }

  assert {
    condition = (
      one([
        for transition in aws_s3_bucket_lifecycle_configuration.quarantine.rule[0].transition :
        transition.days if transition.storage_class == "STANDARD_IA"
      ]) == 30
      && one([
        for transition in aws_s3_bucket_lifecycle_configuration.quarantine.rule[0].transition :
        transition.days if transition.storage_class == "GLACIER_IR"
      ]) == 60
    )
    error_message = "Quarantine originals must transition through the approved FinOps storage classes."
  }

  assert {
    condition = (
      aws_sqs_queue.audio["scan_result"].name == "cntlp-aws-queue-scan-result"
      && aws_sqs_queue.audio["transcode"].name == "cntlp-aws-queue-transcode"
      && aws_sqs_queue.audio["transcode_result"].name == "cntlp-aws-queue-transcode-result"
      && length(aws_sqs_queue.dlq) == 3
    )
    error_message = "The audio pipeline must use three queues with separate DLQs."
  }

  assert {
    condition = (
      aws_sqs_queue.audio["transcode"].visibility_timeout_seconds == 900
      && aws_sqs_queue.audio["scan_result"].visibility_timeout_seconds == 60
      && aws_sqs_queue.audio["transcode_result"].visibility_timeout_seconds == 60
    )
    error_message = "Queue visibility timeouts must match the consumer processing windows."
  }

  assert {
    condition = contains(
      keys(output.runtime_environment.audio_api),
      "SCAN_RESULT_QUEUE_URL",
    )
    error_message = "The API runtime contract must include the scan-result queue URL."
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.audio) == 0
      && length(aws_iam_role.workload) == 0
    )
    error_message = "Costed and OIDC-dependent resources must remain opt-in."
  }
}

run "security_delivery_and_workload_iam" {
  command = plan

  variables {
    aws_account_id      = "123456789012"
    aws_region          = "ap-northeast-2"
    owner               = "team-audio"
    data_class          = "user-audio"
    web_allowed_origins = ["https://audio.example.com"]

    enable_cloudfront          = true
    cloudfront_public_key_path = "tests/fixtures/cloudfront-public-key.pub"
    enable_workload_iam        = true
    cluster_oidc_provider_arn  = "arn:aws:iam::123456789012:oidc-provider/k8s.example.com"
    cluster_oidc_issuer_url    = "https://k8s.example.com"
  }

  # mock_provider는 aws_iam_policy_document 결과도 임의 문자열로 대체하므로
  # JSON 입력을 받는 Resource 검증에는 유효한 객체를 명시한다.
  override_data {
    target = data.aws_iam_policy_document.transcode_cloudfront
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.workload_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.audio_api
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.audio_events
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.audio_transcode
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  assert {
    condition = (
      aws_cloudfront_origin_access_control.transcode[0].signing_behavior == "always"
      && aws_cloudfront_distribution.audio[0].default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
      && length(aws_cloudfront_distribution.audio[0].default_cache_behavior[0].trusted_key_groups) == 1
    )
    error_message = "CloudFront must use OAC, HTTPS, and a trusted key group."
  }

  assert {
    condition = (
      aws_iam_role.workload["api"].name == "cntlp-aws-api-workload"
      && aws_iam_role.workload["events"].name == "cntlp-aws-queue-events"
      && aws_iam_role.workload["transcode"].name == "cntlp-aws-transcode-workload"
    )
    error_message = "Every audio service account must receive a separate IAM role."
  }
}
