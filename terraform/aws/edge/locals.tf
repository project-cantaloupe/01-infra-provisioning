locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  # Compute Worker가 늘어나면 모든 AWS service 노드를 NLB 대상으로 등록한다.
  worker_nodes = {
    for worker in data.terraform_remote_state.compute.outputs.worker_node_metadata :
    worker.instance_id => worker
  }

  node_ports = {
    http   = var.audio_ingress_http_node_port
    health = var.audio_ingress_health_node_port
  }

  # https:// 접두사와 마지막 /를 제거해 IAM OIDC 조건 키로 사용한다.
  cluster_oidc_issuer_hostpath = var.cluster_oidc_issuer_url == null ? "" : trimsuffix(
    trimprefix(var.cluster_oidc_issuer_url, "https://"),
    "/",
  )

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
