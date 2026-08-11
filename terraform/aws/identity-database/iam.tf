# Keycloak 이 서기 전에 있어야 하는 두 시크릿의 읽기 권한을 Worker Role 에 붙인다.
#
# ⚠️ **둘 다 2026-08-11 까지 terraform 밖에 있었다.** 손으로 만든 것을 import 로
# 들였다 → tasks/doing/018_iam-outside-terraform.md
#
# ── 왜 keycloak 스택이 아니라 여기인가 ────────────────────────────
#
# `terraform/keycloak` 은 provider 가 **Keycloak 이 떠 있어야** 접속한다
# (`initial_login` 기본값이 true 라 plan 부터 로그인한다). 그런데 Keycloak 이
# 뜨려면 ESO 가 bootstrap-admin 을 배달해야 하고, 그러려면 이 정책이 먼저
# 있어야 한다. **정책을 keycloak 스택에 두면 처음부터 짓는 순서가 막힌다.**
#
# 이 스택은 provider 의존이 없고 Keycloak 의 선행이므로 순환이 생기지 않는다.
#
# ── 노드 단위 권한의 한계 ──────────────────────────────────────
#
# 격리 단위가 ServiceAccount 가 아니라 Node 다. 같은 Node 에서 IMDS 에 접근
# 가능한 Pod 는 이 시크릿을 읽을 수 있다. 실질 경계는 ESO 의 SecretStore 를
# 네임스페이스 범위로 둔 것이고, 그건 AWS 권한 경계가 아니라 K8s RBAC 이다.
# → decisions/20260806_cert-manager-node-instance-profile.md

data "terraform_remote_state" "compute" {
  count = var.enable_node_role_policy ? 1 : 0

  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/compute/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# RDS 가 `manage_master_user_password` 로 관리하는 자격증명이다. ARN 을 하드코딩
# 하지 않고 자원에서 읽는다 — 인스턴스를 다시 만들면 ARN 이 바뀐다.
#
# 소비자: `secops/keycloak-db` ExternalSecret
data "aws_iam_policy_document" "identity_database_node" {
  count = var.enable_node_role_policy ? 1 : 0

  statement {
    sid       = "ReadIdentityDatabaseMasterCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.identity.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "identity_database_node" {
  count = var.enable_node_role_policy ? 1 : 0

  # name_prefix 는 `cntlp-aws-identity` 다. 실제 정책 이름과 맞춘다.
  name   = "${local.name_prefix}-database-node"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.identity_database_node[0].json
}

# Keycloak 부트스트랩 관리자 자격증명이다. **이 시크릿 자체는 terraform 이 만들지
# 않는다** — 사람이 넣는다. 시크릿 값을 terraform 이 만들면 tfstate 에 평문으로
# 남기 때문이다 → decisions/20260731_secret-access-no-fallback.md
#
# 그래서 ARN 을 자원 참조가 아니라 이름 패턴으로 적는다. 끝의 `-*` 는 Secrets
# Manager 가 이름 뒤에 붙이는 6자 임의 접미사를 덮는다 — 없으면 매칭이 안 된다.
#
# 소비자: `secops/keycloak-bootstrap-admin` ExternalSecret
#
# ⚠️ **이 자격증명은 임시다.** realm 이 서면 부트스트랩 관리자를 지우고 이 정책도
# 같이 지운다 → terraform/keycloak/provider.tf 의 "이 자격증명은 임시다" 절
data "aws_iam_policy_document" "keycloak_bootstrap_node" {
  count = var.enable_node_role_policy ? 1 : 0

  statement {
    sid    = "ReadKeycloakBootstrapAdmin"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:cntlp/keycloak/bootstrap-admin-*"]
  }
}

resource "aws_iam_role_policy" "keycloak_bootstrap_node" {
  count = var.enable_node_role_policy ? 1 : 0

  # ⚠️ name_prefix(`cntlp-aws-identity`)를 쓰지 않는다. 이 정책은 DB 가 아니라
  # Keycloak 의 것이라 실제 이름이 `cntlp-aws-keycloak-bootstrap-node` 다.
  name   = "${local.org_token}-${local.platform}-keycloak-bootstrap-node"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.keycloak_bootstrap_node[0].json
}
