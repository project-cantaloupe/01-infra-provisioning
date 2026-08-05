output "bucket_names" {
  description = "S3 bucket names used by the audio data path"
  value = {
    quarantine = aws_s3_bucket.quarantine.bucket
    transcode  = aws_s3_bucket.transcode.bucket
  }
}

output "queue_urls" {
  description = "SQS queue URLs injected into audio workloads"
  value = {
    for key, queue in aws_sqs_queue.audio : key => queue.url
  }
}

output "queue_arns" {
  description = "SQS queue ARNs used by IAM and observability configuration"
  value = {
    for key, queue in aws_sqs_queue.audio : key => queue.arn
  }
}

output "dlq_urls" {
  description = "SQS dead-letter queue URLs used for failure inspection"
  value = {
    for key, queue in aws_sqs_queue.dlq : key => queue.url
  }
}

output "cloudfront_domain_name" {
  description = "CloudFront playback domain when enabled"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.audio[0].domain_name : null
}

output "cloudfront_base_url" {
  description = "HTTPS base URL configured as CLOUDFRONT_BASE_URL"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.audio[0].domain_name}" : null
}

output "cloudfront_key_pair_id" {
  description = "CloudFront public key ID configured as CLOUDFRONT_KEY_PAIR_ID"
  value       = var.enable_cloudfront ? aws_cloudfront_public_key.audio[0].id : null
}

output "cloudfront_private_key_secret_arn" {
  description = "Secrets Manager container ARN for the CloudFront signing private key"
  value       = var.enable_cloudfront ? aws_secretsmanager_secret.cloudfront_private_key[0].arn : null
}

output "workload_role_arns" {
  description = "IAM roles annotated on the audio Kubernetes service accounts"
  value = {
    for key, role in aws_iam_role.workload : key => role.arn
  }
}

output "runtime_environment" {
  description = "Non-secret environment contract shared with the Kubernetes manifests"
  value = {
    audio_api = {
      QUARANTINE_BUCKET           = aws_s3_bucket.quarantine.bucket
      ARTIFACT_BUCKET             = aws_s3_bucket.transcode.bucket
      SCAN_RESULT_QUEUE_URL       = aws_sqs_queue.audio["scan_result"].url
      PLAYBACK_URL_MODE           = var.enable_cloudfront ? "cloudfront" : "s3"
      CLOUDFRONT_BASE_URL         = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.audio[0].domain_name}" : null
      CLOUDFRONT_KEY_PAIR_ID      = var.enable_cloudfront ? aws_cloudfront_public_key.audio[0].id : null
      CLOUDFRONT_PRIVATE_KEY_FILE = var.enable_cloudfront ? "/var/run/secrets/cntlp/cloudfront-private-key.pem" : null
    }
    audio_events = {
      SCAN_RESULT_QUEUE_URL      = aws_sqs_queue.audio["scan_result"].url
      TRANSCODE_QUEUE_URL        = aws_sqs_queue.audio["transcode"].url
      TRANSCODE_RESULT_QUEUE_URL = aws_sqs_queue.audio["transcode_result"].url
    }
    audio_transcode = {
      ARTIFACT_BUCKET                = aws_s3_bucket.transcode.bucket
      TRANSCODE_QUEUE_URL            = aws_sqs_queue.audio["transcode"].url
      TRANSCODE_RESULT_QUEUE_URL     = aws_sqs_queue.audio["transcode_result"].url
      SQS_VISIBILITY_TIMEOUT_SECONDS = 900
    }
  }
}
