# RDS가 `manage_master_user_password`로 Secrets Manager에 관리하는 자격증명을
# Kubernetes Workload가 읽어야 한다. Node Instance Profile 경로에서는 Compute
# Stack이 소유한 Worker Role에 이 권한을 붙인다.
#
# 각 Stack이 자기 자원의 권한을 소유하는 경계를 유지한다. Audio Stack이 S3·SQS
# 권한을 붙이듯, Database Stack이 자기 Secret 권한을 붙인다.
#
# 권한 격리 단위가 ServiceAccount가 아니라 Node라는 한계가 있다. 같은 Node에서
# IMDS에 접근 가능한 Pod는 이 Secret을 읽을 수 있다. Calico NetworkPolicy로
# 불필요한 Pod의 IMDS Egress를 차단해 보완한다. 운영 환경에서는 OIDC 기반
# Workload IAM과 앱 전용 DB 사용자로 전환한다.
data "terraform_remote_state" "compute" {
  count = var.enable_node_role_policy || var.enable_control_plane_role_policy ? 1 : 0

  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/compute/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

data "aws_iam_policy_document" "database_node" {
  count = var.enable_node_role_policy ? 1 : 0

  statement {
    sid       = "ReadDatabaseMasterCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.api.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "database_node" {
  count = var.enable_node_role_policy ? 1 : 0

  name   = "${local.name_prefix}-database-node"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.database_node[0].json
}

# Control Plane Node는 Kubernetes Secret을 만들 때 RDS 비밀번호를 읽어야 한다.
# admin.conf로 이미 모든 Kubernetes Secret을 읽을 수 있으므로 이 권한이 노출
# 범위를 넓히지 않는다. 대상 ARN 하나에 액션 하나만 준다.
data "aws_iam_policy_document" "database_control_plane" {
  count = var.enable_control_plane_role_policy ? 1 : 0

  statement {
    sid       = "ReadDatabaseMasterCredentials"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.api.master_user_secret[0].secret_arn]
  }

  # Secret ARN과 접속 주소를 조회하려면 필요하다. 이것이 없으면 운영자가 값을
  # 손으로 옮겨 적어야 하고, 문서에 적힌 절차가 그대로 동작하지 않는다.
  # 대상 DB 하나에 대한 읽기이며 자격증명을 노출하지 않는다.
  statement {
    sid       = "DescribeApiDatabase"
    effect    = "Allow"
    actions   = ["rds:DescribeDBInstances"]
    resources = [aws_db_instance.api.arn]
  }
}

resource "aws_iam_role_policy" "database_control_plane" {
  count = var.enable_control_plane_role_policy ? 1 : 0

  name   = "${local.name_prefix}-database-control-plane"
  role   = data.terraform_remote_state.compute[0].outputs.control_plane_role_name
  policy = data.aws_iam_policy_document.database_control_plane[0].json
}
