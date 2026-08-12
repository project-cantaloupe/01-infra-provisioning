data "aws_partition" "current" {}

locals {
  regional_ec2_resource_arns = [
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:fleet/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:volume/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:network-interface/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:launch-template/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:spot-instances-request/*",
  ]

  launch_resource_arns = [
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::image/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::snapshot/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:capacity-reservation/*",
    "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:placement-group/*",
  ]
}

# Self-managed Kubernetes에는 IRSA와 EKS Pod Identity가 없다. Karpenter
# Controller를 Control Plane Node에 고정하고 그 Node의 Instance Profile에서
# 임시 자격증명을 받는다. 이 정책은 Karpenter가 만든 태그가 있는 EC2만
# 생성·변경·삭제하며, 기존 Service Worker Role만 EC2에 전달할 수 있다.
data "aws_iam_policy_document" "karpenter_controller" {
  count = var.enable_controller_foundation ? 1 : 0

  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = local.launch_resource_arns
  }

  statement {
    sid    = "AllowScopedEC2LaunchTemplateAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.kubernetes_cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    resources = local.regional_ec2_resource_arns

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.kubernetes_cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.kubernetes_cluster_name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceCreationTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = local.regional_ec2_resource_arns

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.kubernetes_cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.kubernetes_cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values = [
        "RunInstances",
        "CreateFleet",
        "CreateLaunchTemplate",
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.kubernetes_cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.kubernetes_cluster_name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "eks:eks-cluster-name",
        "karpenter.sh/nodeclaim",
        "Name",
      ]
    }
  }

  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.kubernetes_cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowPassingWorkerRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.worker_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # Karpenter 1.14의 Instance Profile garbage collector는 사전 지정된 Profile을
  # 사용해도 전체 목록을 조회한다. IAM List API는 Resource 수준 제한을 지원하지
  # 않으므로 공식 Controller 정책과 같이 읽기 동작 하나만 별도로 허용한다.
  statement {
    sid       = "AllowUnscopedInstanceProfileListAction"
    effect    = "Allow"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["*"]
  }

  statement {
    sid     = "AllowWorkerInstanceProfileRead"
    effect  = "Allow"
    actions = ["iam:GetInstanceProfile"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${var.aws_account_id}:instance-profile/${local.worker_instance_profile_name}",
      # 사전 지정 Profile로 전환하기 전에 Karpenter가 만든 Profile의 삭제 Finalizer가
      # NoSuchEntity를 확인할 수 있게 생성형 Prefix의 읽기만 허용한다.
      "arn:${data.aws_partition.current.partition}:iam::${var.aws_account_id}:instance-profile/${local.kubernetes_cluster_name}_*",
    ]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.enable_controller_foundation ? 1 : 0

  name   = local.controller_policy_name
  role   = local.control_plane_role_name
  policy = data.aws_iam_policy_document.karpenter_controller[0].json

  lifecycle {
    precondition {
      condition = (
        local.control_plane_role_name != null
        && local.worker_role_arn != null
        && local.worker_instance_profile_name != null
      )
      error_message = "Compute state must expose enabled Control Plane and Worker Instance Profiles before the Karpenter controller foundation is enabled."
    }
  }
}
