locals {
  org_token   = "cntlp"
  platform    = "aws"
  name_prefix = "${local.org_token}-${local.platform}"

  packer_name = "${local.name_prefix}-cicd-packer"

  bootstrap_secret_name = "${local.name_prefix}-cicd-worker-bootstrap"
  boot_test_node_name   = "${local.name_prefix}-wk-99"

  # 기존 Compute state에는 Instance Profile 전용 output이 아직 없을 수 있다.
  # Compute Stack은 Worker Role과 Instance Profile에 같은 이름을 사용하므로
  # 현재 output을 fallback으로 두고 파괴적인 Compute apply를 요구하지 않는다.
  worker_role_name = var.enable_bootstrap_foundation ? (
    data.terraform_remote_state.compute[0].outputs.worker_role_name
  ) : null
  worker_instance_profile_name = var.enable_bootstrap_foundation ? try(
    data.terraform_remote_state.compute[0].outputs.worker_instance_profile_name,
    data.terraform_remote_state.compute[0].outputs.worker_role_name,
  ) : null

  default_tags = {
    org          = local.org_token
    owner        = var.owner
    "managed-by" = "terraform"
    lifecycle    = "permanent"
    platform     = local.platform
    component    = "cicd"
  }
}
