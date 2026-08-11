# 장기 Access Key 없이 cert-manager ServiceAccount만 Route53을 변경한다.
# Self-managed Kubernetes OIDC 구성이 준비되기 전에는 생성하지 않는다.
resource "aws_iam_role" "cert_manager" {
  count = var.enable_cert_manager_iam ? 1 : 0

  name               = "${local.name_prefix}-cert-manager-dns01"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume_role[0].json

  tags = {
    Name      = "${local.name_prefix}-cert-manager-dns01"
    component = "cicd"
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  count = var.enable_cert_manager_iam ? 1 : 0

  name   = "${local.name_prefix}-cert-manager-route53"
  role   = aws_iam_role.cert_manager[0].id
  policy = data.aws_iam_policy_document.cert_manager_route53[0].json
}

# cert-manager 가 Node Instance Profile(IMDS)로 Route53 DNS-01 을 푼다.
# 위의 IRSA 경로와 배타가 아니라 **지금 실제로 도는 경로**다.
#
# 각 Stack 이 자기 자원의 권한을 소유하는 경계를 지킨다 — Route53 존은
# 이 Stack 의 `route53_zone_id` 가 소유하므로 그 존에 대한 권한도 여기 산다.
resource "aws_iam_role_policy" "cert_manager_node" {
  count = var.enable_cert_manager_node_policy ? 1 : 0

  name   = "${local.name_prefix}-cert-manager-node"
  role   = data.terraform_remote_state.compute.outputs.worker_role_name
  policy = data.aws_iam_policy_document.cert_manager_node[0].json
}
