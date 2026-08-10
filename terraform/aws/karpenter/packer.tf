data "aws_iam_policy_document" "packer_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "packer" {
  name               = local.packer_name
  assume_role_policy = data.aws_iam_policy_document.packer_assume_role.json

  tags = {
    Name = local.packer_name
  }
}

# AWS 관리형 정책을 통째로 붙이지 않고 Packer Builder가 SSM managed instance로
# 등록되고 Session Manager 채널을 여는 데 필요한 동작만 inline으로 둔다.
data "aws_iam_policy_document" "packer_ssm" {
  statement {
    sid    = "ReportManagedInstanceState"
    effect = "Allow"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:DescribeDocument",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:PutInventory",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "OpenSessionManagerChannels"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ReceiveLegacyEc2Messages"
    effect = "Allow"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "packer_ssm" {
  name   = "${local.packer_name}-ssm"
  role   = aws_iam_role.packer.id
  policy = data.aws_iam_policy_document.packer_ssm.json
}

resource "aws_iam_instance_profile" "packer" {
  name = local.packer_name
  role = aws_iam_role.packer.name

  tags = {
    Name = local.packer_name
  }
}

# Session Manager는 Builder가 바깥으로 연결하므로 inbound 규칙이 필요 없다.
resource "aws_security_group" "packer" {
  name        = "${local.packer_name}-sg"
  description = "Outbound-only access for the temporary Packer builder"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "${local.packer_name}-sg"
  }
}

# Ubuntu, Kubernetes, Tailscale 저장소와 SSM endpoint를 Private Subnet의 NAT를
# 통해 사용한다. Builder는 inbound가 없고 빌드가 끝나면 종료된다.
resource "aws_vpc_security_group_egress_rule" "packer" {
  security_group_id = aws_security_group.packer.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Package repositories and AWS Systems Manager"
}
