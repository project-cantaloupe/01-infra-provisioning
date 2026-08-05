locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  quarantine_bucket_name = "${local.name_prefix}-quarantine"
  transcode_bucket_name  = "${local.name_prefix}-transcode"

  queue_names = {
    scan_result      = "${local.name_prefix}-queue-scan-result"
    transcode        = "${local.name_prefix}-queue-transcode"
    transcode_result = "${local.name_prefix}-queue-transcode-result"
  }

  workload_service_accounts = {
    api       = var.audio_api_service_account
    events    = var.audio_events_service_account
    transcode = var.audio_transcode_service_account
  }

  # https:// 접두사와 마지막 /를 제거해 IAM OIDC 조건 키로 사용한다.
  cluster_oidc_issuer_hostpath = var.cluster_oidc_issuer_url == null ? "" : trimsuffix(
    trimprefix(var.cluster_oidc_issuer_url, "https://"),
    "/",
  )

  cloudfront_origin_id = "${local.name_prefix}-transcode-s3"

  default_tags = {
    org          = local.org_token
    owner        = var.owner
    "managed-by" = "terraform"
    "data-class" = var.data_class
    lifecycle    = "permanent"
    platform     = local.platform
    component    = "api"
  }
}
