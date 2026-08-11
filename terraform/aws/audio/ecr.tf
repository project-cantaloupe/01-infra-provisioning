locals {
  ecr_repositories = {
    api    = "app-audio-api"
    web    = "app-audio-web"
    worker = "app-audio-worker"
  }
}

# AWS runtime images use immutable commit-SHA tags. Harbor can remain available for
# internal validation, but Argo CD will be switched to these ECR image URLs.
resource "aws_ecr_repository" "audio" {
  for_each = var.enable_ecr ? local.ecr_repositories : {}

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.default_tags, {
    Name      = each.value
    component = "audio-${each.key}"
  })
}

resource "aws_ecr_lifecycle_policy" "audio" {
  for_each = aws_ecr_repository.audio

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the most recent ${var.ecr_tag_retention_count} tagged release images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_tag_retention_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# This provider is account-wide. If it already exists, import it into this address
# before apply instead of creating a duplicate provider.
resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.enable_ecr ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  tags            = merge(local.default_tags, { Name = "github-actions" })
}

data "aws_iam_policy_document" "github_actions_ecr_assume_role" {
  count = var.enable_ecr ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub can encode a branch or an environment in the OIDC subject. Limit
    # the role to this repository while allowing either supported subject form.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_organization}/${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr" {
  count = var.enable_ecr ? 1 : 0

  name               = "${local.name_prefix}-github-actions-ecr-publish"
  assume_role_policy = data.aws_iam_policy_document.github_actions_ecr_assume_role[0].json

  tags = merge(local.default_tags, {
    Name      = "${local.name_prefix}-github-actions-ecr-publish"
    component = "ci"
  })
}

data "aws_iam_policy_document" "github_actions_ecr_publish" {
  count = var.enable_ecr ? 1 : 0

  statement {
    sid       = "GetEcrAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushAudioImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repository in aws_ecr_repository.audio : repository.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_publish" {
  count = var.enable_ecr ? 1 : 0

  name   = "${local.name_prefix}-ecr-publish"
  role   = aws_iam_role.github_actions_ecr[0].id
  policy = data.aws_iam_policy_document.github_actions_ecr_publish[0].json
}

data "aws_iam_policy_document" "worker_ecr_pull" {
  count = var.enable_ecr ? 1 : 0

  statement {
    sid       = "GetEcrAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PullAudioImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [for repository in aws_ecr_repository.audio : repository.arn]
  }
}

resource "aws_iam_role_policy" "worker_ecr_pull" {
  count = var.enable_ecr ? 1 : 0

  name   = "${local.name_prefix}-ecr-pull"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.worker_ecr_pull[0].json
}
