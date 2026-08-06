# NLB와 NLB 전용 규칙은 같은 Edge 상태에서 함께 생성·삭제한다.
resource "aws_security_group" "audio_nlb" {
  name        = "${local.name_prefix}-audio-nlb-sg"
  description = "Public access rules for the audio service NLB"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "${local.name_prefix}-audio-nlb-sg"
  }
}

# Gateway에 TLS server가 없어 요청이 평문 HTTP로 오가고, audio-api는
# AUTH_MODE=development 동안 X-Cantaloupe-Subject 헤더를 그대로 신뢰한다.
# 따라서 Source CIDR 제한이 현재 유일한 접근 통제다. Cognito JWT 검증과
# TLS가 붙기 전에는 이 목록을 넓히지 않는다.
resource "aws_vpc_security_group_ingress_rule" "audio_nlb_http" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.audio_nlb.id
  description       = "Audio NLB HTTP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

# NLB가 Istio ingress gateway의 HTTP와 readiness NodePort에만 접근한다.
resource "aws_vpc_security_group_egress_rule" "audio_nlb_to_worker" {
  for_each = toset([
    tostring(local.node_ports.http),
    tostring(local.node_ports.health),
  ])

  security_group_id            = aws_security_group.audio_nlb.id
  description                  = "NLB to Istio ingress gateway NodePort ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = data.terraform_remote_state.network.outputs.worker_security_group_id
}

# Worker는 인터넷 전체가 아니라 NLB Security Group에서 시작한 요청만 받는다.
resource "aws_vpc_security_group_ingress_rule" "worker_from_audio_nlb" {
  for_each = toset([
    tostring(local.node_ports.http),
    tostring(local.node_ports.health),
  ])

  security_group_id            = data.terraform_remote_state.network.outputs.worker_security_group_id
  description                  = "Istio ingress gateway NodePort ${each.value} from the audio NLB"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.audio_nlb.id
}
