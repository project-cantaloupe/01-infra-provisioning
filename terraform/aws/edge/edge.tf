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

# TCP listener만 사용해 TLS 종료 지점을 Istio Gateway로 유지한다.
#
# 443 listener는 두지 않는다. audio-gateway의 server 블록이 HTTP 80 하나뿐이라
# Envoy가 443을 바인딩하지 않고, Health Check는 32021을 보므로 Target이
# healthy로 보이는 채 443만 조용히 끊긴다. Gateway에 TLS server와 인증서가
# 생기면 그때 listener와 Target Group을 함께 추가한다.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.audio.arn
  port              = 80
  protocol          = "TCP"

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
