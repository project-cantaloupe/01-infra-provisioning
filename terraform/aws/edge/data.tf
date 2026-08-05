# Network 상태에서 VPC, Public Subnet, Worker Security Group을 읽는다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# Compute 상태에서 NLB 대상이 되는 AWS Worker 인스턴스를 읽는다.
data "terraform_remote_state" "compute" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/compute/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# cert-manager가 Route53 DNS-01 레코드만 변경하도록 제한한 신뢰 정책이다.
data "aws_iam_policy_document" "cert_manager_assume_role" {
  count = var.enable_cert_manager_iam ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_issuer_hostpath}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }
  }
}

data "aws_iam_policy_document" "cert_manager_route53" {
  count = var.enable_cert_manager_iam ? 1 : 0

  statement {
    sid    = "ChangeDns01Records"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]
  }

  statement {
    sid       = "ReadDns01ChangeStatus"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid       = "DiscoverHostedZone"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}
