# raft 데이터는 인스턴스의 EBS에 있다. 인스턴스를 잃으면 같이 잃는다.
# `vault operator raft snapshot save` 결과를 여기 올린다.
resource "aws_s3_bucket" "snapshots" {
  bucket = "${local.name_prefix}-vault-snapshots"

  # 실수로 지우는 것을 막는다. 스냅샷이 없으면 인스턴스 손실이 곧 데이터 손실이다.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-vault-snapshots"
  }
}

resource "aws_s3_bucket_versioning" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  versioning_configuration {
    status = "Enabled"
  }
}

# **스냅샷은 시크릿 전부를 담는다.** raft 스냅샷은 unseal되지 않은 상태로
# 암호화돼 있지만, unseal KMS 키에 접근할 수 있는 주체에게는 평문과 같다.
# 그래서 버킷 암호화를 따로 건다.
#
# bucket_key_enabled 로 객체마다 KMS를 호출하지 않고 버킷 키를 쓴다.
# 암호화 강도는 같고 KMS 요청 비용이 준다 — FinOps가 평가 기준인 프로젝트다.
resource "aws_s3_bucket_server_side_encryption_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.unseal.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "snapshots" {
  bucket                  = aws_s3_bucket.snapshots.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 오래된 스냅샷을 지운다. 시크릿을 담은 객체를 무한히 쌓지 않는다.
resource "aws_s3_bucket_lifecycle_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  rule {
    id     = "expire-old-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = var.snapshot_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# 평문 전송을 거부한다.
resource "aws_s3_bucket_policy" "snapshots_tls_only" {
  bucket = aws_s3_bucket.snapshots.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.snapshots.arn,
        "${aws_s3_bucket.snapshots.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
