locals {
  workload_role_names = {
    api       = "${local.name_prefix}-api-workload"
    events    = "${local.name_prefix}-queue-events"
    transcode = "${local.name_prefix}-transcode-workload"
  }

  workload_components = {
    api       = "api"
    events    = "queue"
    transcode = "transcode"
  }
}

data "aws_iam_policy_document" "workload_assume_role" {
  for_each = var.enable_workload_iam ? local.workload_service_accounts : {}

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_issuer_hostpath}:sub"
      values   = ["system:serviceaccount:${var.audio_namespace}:${each.value}"]
    }
  }
}

# 각 Kubernetes ServiceAccount는 필요한 AWS API만 호출하는 별도 Role을 사용한다.
resource "aws_iam_role" "workload" {
  for_each = var.enable_workload_iam ? local.workload_service_accounts : {}

  name               = local.workload_role_names[each.key]
  assume_role_policy = data.aws_iam_policy_document.workload_assume_role[each.key].json

  tags = {
    Name      = local.workload_role_names[each.key]
    component = local.workload_components[each.key]
  }
}

data "aws_iam_policy_document" "audio_api" {
  count = local.build_audio_policies ? 1 : 0

  statement {
    sid       = "ReadQuarantineBucketMetadata"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.quarantine.arn]
  }

  # GuardDuty를 사용하지 않으므로 API가 업로드 검증 후 직접 스캔 상태 태그를 기록한다.
  statement {
    sid    = "CreateAndVerifySourceUploads"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.quarantine.arn}/incoming/*"]
  }

  # EventBridge를 대체해 API가 scan-result 계약 메시지를 직접 발행한다.
  statement {
    sid       = "PublishScanResults"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.audio["scan_result"].arn]
  }

  dynamic "statement" {
    for_each = var.enable_cloudfront ? [1] : []

    content {
      sid       = "ReadCloudFrontSigningKey"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.cloudfront_private_key[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.enable_cloudfront ? [] : [1]

    content {
      sid       = "SignDirectArtifactReads"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.transcode.arn}/audios/*"]
    }
  }
}

resource "aws_iam_role_policy" "audio_api" {
  count = var.enable_workload_iam ? 1 : 0

  name   = "${local.name_prefix}-api-storage"
  role   = aws_iam_role.workload["api"].id
  policy = data.aws_iam_policy_document.audio_api[0].json
}

data "aws_iam_policy_document" "audio_events" {
  count = local.build_audio_policies ? 1 : 0

  statement {
    sid    = "ConsumeAudioResults"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [
      aws_sqs_queue.audio["scan_result"].arn,
      aws_sqs_queue.audio["transcode_result"].arn,
    ]
  }

  statement {
    sid       = "PublishTranscodeJobs"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.audio["transcode"].arn]
  }
}

resource "aws_iam_role_policy" "audio_events" {
  count = var.enable_workload_iam ? 1 : 0

  name   = "${local.name_prefix}-queue-events"
  role   = aws_iam_role.workload["events"].id
  policy = data.aws_iam_policy_document.audio_events[0].json
}

data "aws_iam_policy_document" "audio_transcode" {
  count = local.build_audio_policies ? 1 : 0

  statement {
    sid    = "ConsumeTranscodeJobs"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.audio["transcode"].arn]
  }

  statement {
    sid       = "PublishTranscodeResults"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.audio["transcode_result"].arn]
  }

  statement {
    sid     = "ReadAudioBuckets"
    effect  = "Allow"
    actions = ["s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.quarantine.arn,
      aws_s3_bucket.transcode.arn,
    ]
  }

  statement {
    sid    = "ReadCleanSourceVersion"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.quarantine.arn}/incoming/*"]
  }

  statement {
    sid    = "WriteTranscodeArtifacts"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.transcode.arn}/audios/*"]
  }

  statement {
    sid       = "ListArtifactMultipartUploads"
    effect    = "Allow"
    actions   = ["s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.transcode.arn]
  }
}

resource "aws_iam_role_policy" "audio_transcode" {
  count = var.enable_workload_iam ? 1 : 0

  name   = "${local.name_prefix}-transcode"
  role   = aws_iam_role.workload["transcode"].id
  policy = data.aws_iam_policy_document.audio_transcode[0].json
}

# Node Instance Profile 경로에서는 세 ServiceAccount 권한의 합집합을 Compute
# Stack의 Worker Role에 붙인다. 같은 Node에서 IMDS에 접근 가능한 Pod는 이 권한을
# 모두 사용할 수 있으므로 격리 단위가 ServiceAccount가 아니라 Node다. Calico
# NetworkPolicy로 불필요한 Pod의 IMDS Egress를 차단해 보완하지만 Pod별 IAM
# 격리를 대체하지는 않는다.
data "aws_iam_policy_document" "audio_node" {
  count = var.enable_node_role_policy ? 1 : 0

  source_policy_documents = [
    data.aws_iam_policy_document.audio_api[0].json,
    data.aws_iam_policy_document.audio_events[0].json,
    data.aws_iam_policy_document.audio_transcode[0].json,
  ]
}

resource "aws_iam_role_policy" "audio_node" {
  count = var.enable_node_role_policy ? 1 : 0

  name   = "${local.name_prefix}-audio-node"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.audio_node[0].json
}

# CloudWatch Exporter는 AWS service Worker에서 실행하고 EC2 Instance Profile의
# 단기 자격증명을 사용한다. S3 객체나 로그를 읽지 않고 CloudWatch metric과
# metric만 조회한다.
data "aws_iam_policy_document" "finops_cloudwatch_read" {
  count = var.enable_node_role_policy ? 1 : 0

  statement {
    sid    = "ReadCloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "finops_cloudwatch_read" {
  count = var.enable_node_role_policy ? 1 : 0

  name   = "cntlp-finops-cloudwatch-read"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.finops_cloudwatch_read[0].json
}
