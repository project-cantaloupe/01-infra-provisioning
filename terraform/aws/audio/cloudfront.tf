# 서명 검증에는 공개키만 등록하며 개인키는 Terraform 값으로 전달하지 않는다.
resource "aws_cloudfront_public_key" "audio" {
  count = var.enable_cloudfront ? 1 : 0

  # 키를 교체하면 encoded_key 변경이 재생성을 강제한다. 기본 순서인 삭제 후 생성은
  # 실패한다. Key Group이 참조 중인 공개키는 CloudFront가 삭제를 거부하기 때문이다.
  # 새 키를 먼저 만들고 Key Group이 그것을 가리킨 뒤 옛 키를 지운다.
  #
  # 이름이 겹치면 생성 단계에서 충돌하므로 접미사를 붙여 매번 다른 이름을 쓴다.
  name        = "${local.name_prefix}-api-playback-${substr(sha256(try(file("${path.module}/${var.cloudfront_public_key_path}"), "")), 0, 8)}"
  comment     = "Public key used to verify Cantaloupe audio playback signed URLs"
  encoded_key = try(file("${path.module}/${var.cloudfront_public_key_path}"), "")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_key_group" "audio" {
  count = var.enable_cloudfront ? 1 : 0

  name    = "${local.name_prefix}-api-playback"
  comment = "Trusted key group for private audio playback"
  items   = [aws_cloudfront_public_key.audio[0].id]
}

resource "aws_cloudfront_origin_access_control" "transcode" {
  count = var.enable_cloudfront ? 1 : 0

  name                              = "${local.name_prefix}-transcode-oac"
  description                       = "CloudFront access to the private transcode bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "audio" {
  count = var.enable_cloudfront ? 1 : 0

  name    = "${local.name_prefix}-api-playback"
  comment = "CORS and browser security headers for audio playback"

  cors_config {
    access_control_allow_credentials = false
    access_control_max_age_sec       = 600
    origin_override                  = true

    access_control_allow_headers {
      items = ["Range"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = sort(tolist(var.web_allowed_origins))
    }

    access_control_expose_headers {
      items = ["Accept-Ranges", "Content-Length", "Content-Range", "ETag"]
    }
  }

  security_headers_config {
    content_type_options {
      override = true
    }

    referrer_policy {
      override        = true
      referrer_policy = "no-referrer"
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      override                   = true
      preload                    = false
    }
  }
}

resource "aws_cloudfront_distribution" "audio" {
  count = var.enable_cloudfront ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "Private Cantaloupe audio playback"
  price_class     = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.transcode.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.transcode[0].id
    origin_id                = local.cloudfront_origin_id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    default_ttl                = 3600
    max_ttl                    = 86400
    min_ttl                    = 0
    response_headers_policy_id = aws_cloudfront_response_headers_policy.audio[0].id
    target_origin_id           = local.cloudfront_origin_id
    trusted_key_groups         = [aws_cloudfront_key_group.audio[0].id]
    viewer_protocol_policy     = "redirect-to-https"

    forwarded_values {
      headers = [
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "Origin",
      ]
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name      = "${local.name_prefix}-api-playback"
    component = "api"
  }
}

data "aws_iam_policy_document" "transcode_cloudfront" {
  count = var.enable_cloudfront ? 1 : 0

  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.transcode.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.audio[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "transcode_cloudfront" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.transcode.id
  policy = data.aws_iam_policy_document.transcode_cloudfront[0].json

  depends_on = [aws_s3_bucket_public_access_block.transcode]
}

# Secret 컨테이너만 생성한다. 개인키 값은 apply 후 별도 명령으로 등록한다.
resource "aws_secretsmanager_secret" "cloudfront_private_key" {
  count = var.enable_cloudfront ? 1 : 0

  name                    = "${local.name_prefix}-api-cloudfront-key"
  description             = "Private key used by audio-api to sign CloudFront playback URLs"
  recovery_window_in_days = 7

  tags = {
    Name      = "${local.name_prefix}-api-cloudfront-key"
    component = "api"
  }
}
