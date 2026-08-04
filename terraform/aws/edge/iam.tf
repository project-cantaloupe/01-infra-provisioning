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
