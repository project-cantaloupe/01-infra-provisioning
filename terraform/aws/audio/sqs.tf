locals {
  queue_definitions = {
    scan_result = {
      name               = local.queue_names.scan_result
      visibility_timeout = 60
    }
    transcode = {
      name               = local.queue_names.transcode
      visibility_timeout = 900
    }
    transcode_result = {
      name               = local.queue_names.transcode_result
      visibility_timeout = 60
    }
  }
}

# 각 소비자 Queue는 독립 DLQ를 사용해 실패 원인과 재처리 범위를 분리한다.
resource "aws_sqs_queue" "dlq" {
  for_each = local.queue_definitions

  name                      = "${each.value.name}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Name      = "${each.value.name}-dlq"
    component = "queue"
  }
}

resource "aws_sqs_queue" "audio" {
  for_each = local.queue_definitions

  name                       = each.value.name
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = each.value.visibility_timeout
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.queue_max_receive_count
  })

  tags = {
    Name      = each.value.name
    component = "queue"
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "audio" {
  for_each = local.queue_definitions

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.audio[each.key].arn]
  })
}
