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
  count = var.enable_workload_iam ? 1 : 0

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
  count = var.enable_workload_iam ? 1 : 0

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
  count = var.enable_workload_iam ? 1 : 0

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
