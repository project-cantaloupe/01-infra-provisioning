# 브라우저가 Presigned URL로 원본을 직접 올리는 비공개 격리 버킷이다.
resource "aws_s3_bucket" "quarantine" {
  bucket = local.quarantine_bucket_name

  tags = {
    Name      = local.quarantine_bucket_name
    component = "quarantine"
  }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  cors_rule {
    allowed_headers = ["content-type", "x-amz-checksum-sha256", "x-amz-sdk-checksum-algorithm"]
    allowed_methods = ["HEAD", "PUT"]
    allowed_origins = sort(tolist(var.web_allowed_origins))
    expose_headers  = ["ETag", "x-amz-checksum-sha256", "x-amz-version-id"]
    max_age_seconds = 300
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "transition-quarantine-objects"
    status = "Enabled"

    filter {
      prefix = "incoming/"
    }

    transition {
      days          = var.quarantine_standard_ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.quarantine_glacier_ir_transition_days
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.quarantine]
}

# Worker가 생성한 MP3와 waveform JSON을 보관하는 비공개 결과 버킷이다.
resource "aws_s3_bucket" "transcode" {
  bucket = local.transcode_bucket_name

  tags = {
    Name      = local.transcode_bucket_name
    component = "transcode"
  }
}

resource "aws_s3_bucket_public_access_block" "transcode" {
  bucket = aws_s3_bucket.transcode.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "transcode" {
  bucket = aws_s3_bucket.transcode.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "transcode" {
  bucket = aws_s3_bucket.transcode.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transcode" {
  bucket = aws_s3_bucket.transcode.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "transcode" {
  bucket = aws_s3_bucket.transcode.id

  cors_rule {
    allowed_headers = ["Range"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = sort(tolist(var.web_allowed_origins))
    expose_headers  = ["Accept-Ranges", "Content-Length", "Content-Range", "ETag"]
    max_age_seconds = 600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "transcode" {
  bucket = aws_s3_bucket.transcode.id

  rule {
    id     = "clean-old-artifact-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.transcode]
}
