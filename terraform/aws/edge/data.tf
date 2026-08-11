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

# ── cert-manager 의 Node Instance Profile 경로 ────────────────────────
#
# 위의 `cert_manager_route53` 은 **IRSA 경로**용이고 아직 안 만들어졌다.
# 실제로 지금 도는 것은 Worker Role 에 붙은 인라인 정책이다
# → decisions/20260806_cert-manager-node-instance-profile.md
#
# ⚠️ **둘은 권한 범위가 다르다.** 아래가 더 좁다.
#
#   IRSA 경로       ChangeResourceRecordSets 에 조건 없음 + ListHostedZonesByName
#   Node 경로(아래)  TXT + `_acme-challenge.*` 로 조건, ListHostedZonesByName 없음
#
# 좁은 쪽이 실제로 쓰이는 것이고, 넓은 쪽을 지금 만들 이유가 없다.
# IRSA 로 전환할 때 위 문서를 이쪽에 맞춰 좁힌다.
#
# ⚠️ **이 자원은 2026-08-11 까지 terraform 밖에 있었다.** 손으로 만든 것을
# import 로 들였다 → tasks/doing/018_iam-outside-terraform.md
#
# Worker Role 이름은 위의 `terraform_remote_state.compute` 에서 온다 —
# NLB 대상 인스턴스를 읽으려고 이미 선언돼 있어 새로 만들지 않았다.
data "aws_iam_policy_document" "cert_manager_node" {
  count = var.enable_cert_manager_node_policy ? 1 : 0

  # ACME 챌린지의 전파 상태를 폴링한다. change ID 는 미리 알 수 없어 와일드카드다.
  statement {
    sid       = "ReadAcmeChangeStatus"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  # 자기가 만든 TXT 레코드를 다시 읽어 확인한다. 존 하나로 좁혀져 있다.
  statement {
    sid       = "ReadEchoprismRecords"
    effect    = "Allow"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]
  }

  # 쓰기는 세 겹으로 좁힌다 — 존 하나, 이름 `_acme-challenge.*`, 타입 TXT.
  # 이 조건이 없으면 서비스 A 레코드를 지울 수 있다.
  #
  # ⚠️ `route53:ListHostedZonesByName` 은 **주지 않는다.** ClusterIssuer 가
  # `hostedZoneID` 를 명시하므로 이름으로 찾을 일이 없다. 그 대신 존 ID 를
  # 비우면 AccessDenied 로 죽는다 — 두 파일이 서로를 전제한다.
  statement {
    sid       = "WriteAcmeChallengeRecordsOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.*"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }
}
