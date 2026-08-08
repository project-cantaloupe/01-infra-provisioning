# Terraform은 Secret 컨테이너와 정확한 IAM 권한만 관리한다. Tailscale OAuth
# Client Secret과 kubeadm token 값은 Terraform state에 저장하지 않는다.
resource "aws_secretsmanager_secret" "tailscale_oauth" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  name                    = local.tailscale_oauth_secret_name
  description             = "Restricted Tailscale OAuth credential for ephemeral Karpenter Workers"
  recovery_window_in_days = 0

  tags = {
    Name         = local.tailscale_oauth_secret_name
    lifecycle    = "temporary"
    "expires-on" = var.bootstrap_expires_on
    "data-class" = "credential"
  }
}

resource "aws_secretsmanager_secret" "kubeadm_join" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  name                    = local.kubeadm_join_secret_name
  description             = "Automatically rotated kubeadm join credential for Karpenter Workers"
  recovery_window_in_days = 0

  tags = {
    Name         = local.kubeadm_join_secret_name
    lifecycle    = "temporary"
    "expires-on" = var.bootstrap_expires_on
    "data-class" = "credential"
  }
}

data "aws_iam_policy_document" "worker_bootstrap_secrets" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  statement {
    sid     = "ReadWorkerBootstrapSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.tailscale_oauth[0].arn,
      aws_secretsmanager_secret.kubeadm_join[0].arn,
    ]
  }
}

resource "aws_iam_role_policy" "worker_bootstrap_secrets" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  name   = local.worker_bootstrap_policy_name
  role   = local.worker_role_name
  policy = data.aws_iam_policy_document.worker_bootstrap_secrets[0].json

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

data "aws_iam_policy_document" "kubeadm_token_rotator" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  statement {
    sid       = "RotateKubeadmJoinSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:PutSecretValue"]
    resources = [aws_secretsmanager_secret.kubeadm_join[0].arn]
  }
}

resource "aws_iam_role_policy" "kubeadm_token_rotator" {
  count = var.enable_bootstrap_foundation ? 1 : 0

  name   = local.kubeadm_rotator_policy_name
  role   = local.control_plane_role_name
  policy = data.aws_iam_policy_document.kubeadm_token_rotator[0].json

  lifecycle {
    precondition {
      condition     = local.control_plane_role_name != null
      error_message = "Compute state must expose an enabled Control Plane Role before bootstrap automation is enabled."
    }
  }
}
