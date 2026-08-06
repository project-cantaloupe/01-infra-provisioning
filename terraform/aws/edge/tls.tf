# ACM 인증서와 DNS 검증 레코드다.
#
# Route53 Hosted Zone이 같은 계정에 있고 도메인이 그 Zone으로 위임돼 있으므로
# 검증 레코드를 Terraform이 직접 만들고, apply가 발급 완료까지 기다린다.
resource "aws_acm_certificate" "audio" {
  count = var.enable_tls ? 1 : 0

  domain_name       = var.public_host
  validation_method = "DNS"

  # 인증서를 교체할 때 Listener가 참조 중인 것을 먼저 지우면 실패한다.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-audio-cert"
  }
}

# domain_validation_options는 apply 전에는 값을 알 수 없다. for_each의 키로
# 쓰면 plan이 "keys cannot be determined"로 실패하므로, SAN 없이 단일 도메인만
# 쓰는 현재 구성에 맞춰 count와 인덱스로 접근한다. SAN을 추가하게 되면 그때
# for_each로 바꾸고 키는 var에서 가져온다.
resource "aws_route53_record" "acm_validation" {
  count = var.enable_tls ? 1 : 0

  zone_id = var.route53_zone_id
  name    = tolist(aws_acm_certificate.audio[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.audio[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.audio[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60

  # 재발급 시 같은 이름의 레코드가 남아 있어도 덮어쓴다.
  allow_overwrite = true
}

# Listener가 검증 완료 전 인증서를 참조하면 생성이 실패한다. 이 리소스가
# 발급 완료를 기다리는 동기화 지점이다.
resource "aws_acm_certificate_validation" "audio" {
  count = var.enable_tls ? 1 : 0

  certificate_arn         = aws_acm_certificate.audio[0].arn
  validation_record_fqdns = [aws_route53_record.acm_validation[0].fqdn]
}
