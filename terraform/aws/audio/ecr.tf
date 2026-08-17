locals {
  ecr_repositories = {
    api    = "app-audio-api"
    web    = "app-audio-web"
    worker = "app-audio-worker"
  }

  # Mirrors of upstream public images. These are NOT application images: we do not
  # build them, we copy them byte for byte so that workloads can be pinned to a
  # registry we control. Kept in a separate map (and a separate resource) so the
  # `component = "audio-*"` tagging stays truthful.
  #
  # Consumers: apps/audio/loadtest/{cronjobs,collector-cronjob}.yaml in
  # 02-k8s-manifests, which run FinOps load generation on `python:3.12-alpine`.
  ecr_mirror_repositories = {
    python = "mirror-python"
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

resource "aws_ecr_repository" "mirror" {
  for_each = var.enable_ecr ? local.ecr_mirror_repositories : {}

  name = each.value

  # IMMUTABLE on purpose. A mirror whose tag can be repointed defeats the reason
  # the mirror exists -- workloads would still be pulling content that can change
  # underneath them, just from a nicer hostname. Refreshing to a newer upstream
  # means pushing a NEW tag (e.g. 3.12-alpine-20260818), not overwriting one.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.default_tags, {
    Name      = each.value
    component = "mirror-${each.key}"
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

# Mirrors deliberately do NOT use the count-based rule above. Expiring a mirrored
# tag by age would delete an image that a pinned workload still references, and the
# breakage would surface at the next CronJob schedule rather than at apply time.
# Untagged layers (failed or superseded pushes) are safe to reap.
resource "aws_ecr_lifecycle_policy" "mirror" {
  for_each = aws_ecr_repository.mirror

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
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

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [var.github_oidc_subject]
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
    resources = concat(
      [for repository in aws_ecr_repository.audio : repository.arn],
      [for repository in aws_ecr_repository.mirror : repository.arn],
    )
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
    # Without the mirror ARNs here the loadtest CronJobs get ImagePullBackOff --
    # and only at their next schedule, long after the apply that "succeeded".
    resources = concat(
      [for repository in aws_ecr_repository.audio : repository.arn],
      [for repository in aws_ecr_repository.mirror : repository.arn],
    )
  }
}

resource "aws_iam_role_policy" "worker_ecr_pull" {
  count = var.enable_ecr ? 1 : 0

  name   = "${local.name_prefix}-ecr-pull"
  role   = data.terraform_remote_state.compute[0].outputs.worker_role_name
  policy = data.aws_iam_policy_document.worker_ecr_pull[0].json
}
