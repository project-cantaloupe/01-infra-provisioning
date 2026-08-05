# Self-managed Kubernetes에는 EKS Pod Identity가 없고, Service Account Issuer를
# 외부에 게시해 IAM OIDC Provider를 등록하는 작업은 단일 Control Plane에서
# apiserver 플래그를 바꿔야 해 이 PoC 범위를 넘는다. 그래서 AWS Service Worker에
# Instance Profile을 붙이고 Pod가 IMDS로 임시 자격증명을 받도록 한다.
#
# 이 Role 자체에는 권한을 넣지 않는다. 실제 권한은 각 Stack이 자기 자원 범위에
# 맞춰 Policy를 붙인다. Audio Stack은 aws/audio에서 S3, SQS, Secrets Manager
# 최소 권한을 연결한다.
#
# 권한 격리 단위가 ServiceAccount가 아니라 Node라는 한계가 있다. 같은 Node에서
# IMDS에 접근 가능한 Pod는 이 Role의 권한을 모두 사용할 수 있다. Calico
# NetworkPolicy로 불필요한 Pod의 IMDS Egress를 차단해 노출을 줄이지만 Pod별 IAM
# 격리를 완전히 대체하지는 않는다. 운영 환경에서는 OIDC 기반 Workload IAM으로
# 전환한다.

data "aws_iam_policy_document" "worker_assume_role" {
  count = var.enable_worker_instance_profile ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker" {
  count = var.enable_worker_instance_profile ? 1 : 0

  name               = local.worker_role_name
  assume_role_policy = data.aws_iam_policy_document.worker_assume_role[0].json

  tags = {
    Name = local.worker_role_name
    role = "service"
  }
}

resource "aws_iam_instance_profile" "worker" {
  count = var.enable_worker_instance_profile ? 1 : 0

  name = local.worker_role_name
  role = aws_iam_role.worker[0].name

  tags = {
    Name = local.worker_role_name
    role = "service"
  }
}
