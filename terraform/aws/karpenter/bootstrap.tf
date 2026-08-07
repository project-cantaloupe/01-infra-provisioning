# Terraform은 Secret 컨테이너와 정확한 IAM 권한만 관리한다. Tailscale auth key와
# kubeadm token 값은 별도 스크립트로 짧게 등록하고 state에는 저장하지 않는다.
resource "aws_secretsmanager_secret" "worker_bootstrap" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  name                    = local.bootstrap_secret_name
  description             = "Short-lived Tailscale and kubeadm credentials for Karpenter Worker lifecycle tests"
  recovery_window_in_days = 0

  tags = {
    Name         = local.bootstrap_secret_name
    lifecycle    = "temporary"
    "expires-on" = var.bootstrap_expires_on
  }
}

data "aws_iam_policy_document" "worker_bootstrap_secret" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  statement {
    sid       = "ReadWorkerBootstrapSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.worker_bootstrap[0].arn]
  }
}

resource "aws_iam_role_policy" "worker_bootstrap_secret" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  name   = "${local.name_prefix}-cicd-worker-bootstrap"
  role   = local.worker_role_name
  policy = data.aws_iam_policy_document.worker_bootstrap_secret[0].json

  lifecycle {
    precondition {
      condition = (
        local.worker_role_name != null
        && local.worker_instance_profile_name != null
      )
      error_message = "Compute state must expose an enabled Worker Role and Instance Profile before the bootstrap foundation is enabled."
    }
  }
}
