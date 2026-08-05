locals {
  # AWS 네이티브 자원 이름의 공통 접두사: cntlp-aws
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  # 단일 Control Plane 이름과 worker_count만큼의 Worker 이름을 만든다.
  control_plane_name = "${local.name_prefix}-cp-01"
  worker_names = [
    for index in range(var.worker_count) :
    format("%s-wk-%02d", local.name_prefix, index + 1)
  ]

  # Service Worker Node에 붙일 Instance Profile과 Role의 공통 이름이다.
  worker_role_name = "${local.name_prefix}-worker-node"

  # Control Plane Node는 Cluster 운영 주체다. Kubernetes Secret을 만들 때
  # 필요한 최소 조회 권한만 각 Stack이 이 Role에 붙인다.
  control_plane_role_name = "${local.name_prefix}-control-plane-node"

  # 모든 AWS 자원에 Provider default_tags로 적용할 필수 태그다.
  # Name과 role처럼 노드별로 달라지는 태그는 각 resource 블록에서 추가한다.
  default_tags = {
    org          = local.org_token
    owner        = var.owner
    "managed-by" = "terraform"
    "data-class" = var.data_class
    lifecycle    = "permanent"
    platform     = local.platform
  }
}
