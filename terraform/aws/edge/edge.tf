# TCP를 그대로 Istio ingress gateway로 전달하는 internet-facing NLB다.
resource "aws_lb" "audio" {
  name                             = "${local.name_prefix}-audio-nlb"
  internal                         = false
  load_balancer_type               = "network"
  ip_address_type                  = "ipv4"
  subnets                          = data.terraform_remote_state.network.outputs.public_subnet_ids
  security_groups                  = [aws_security_group.audio_nlb.id]
  enable_cross_zone_load_balancing = false
  enable_deletion_protection       = var.enable_deletion_protection

  tags = {
    Name = "${local.name_prefix}-audio-nlb"
  }
}

resource "aws_lb_target_group" "http" {
  name        = "${local.name_prefix}-audio-http"
  port        = local.node_ports.http
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  deregistration_delay = 30
  preserve_client_ip   = true

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = tostring(local.node_ports.health)
    path                = "/healthz/ready"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name_prefix}-audio-http"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.audio.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

# TLS를 Istio Gateway가 아니라 NLB에서 종료한다.
#
# 원래 설계는 Gateway 종료였다. 그 경로는 cert-manager DNS-01을 쓰는데,
# terraform/aws/edge의 cert_manager IAM이 cluster_oidc_provider_arn을 요구한다.
# 이 클러스터에는 IAM OIDC Provider가 없고, Workload IAM 대신 Node Instance
# Profile을 쓰기로 한 결정(enable_workload_iam = false)을 되돌리지 않는 한
# 그 전제를 만족시킬 수 없다.
#
# ACM은 무료이고 자동 갱신되며 클러스터에 아무것도 설치하지 않는다. NLB와
# Worker 사이 구간은 VPC 내부이고 Security Group으로 NLB에서 온 트래픽만
# 받는다. Gateway에 TLS server와 인증서를 넣게 되면 이 listener를 TCP
# passthrough로 되돌린다.
resource "aws_lb_listener" "https" {
  count = var.enable_tls ? 1 : 0

  load_balancer_arn = aws_lb.audio.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.audio[0].certificate_arn
  ssl_policy        = var.tls_ssl_policy
  alpn_policy       = "HTTP2Optional"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

# AWS Worker가 늘어나면 같은 Target Group에 자동으로 추가한다.
resource "aws_lb_target_group_attachment" "http" {
  for_each = local.worker_nodes

  target_group_arn = aws_lb_target_group.http.arn
  target_id        = each.key
  port             = local.node_ports.http
}

resource "aws_route53_record" "audio" {
  count = var.create_dns_record ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.public_host
  type    = "A"

  alias {
    name                   = aws_lb.audio.dns_name
    zone_id                = aws_lb.audio.zone_id
    evaluate_target_health = true
  }
}
