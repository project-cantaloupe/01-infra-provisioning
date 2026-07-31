# Vault 주소와 토큰을 코드에 넣지 않는다. VAULT_ADDR / VAULT_TOKEN 을 읽는다.
#
# 토큰의 출처는 둘 다 된다. 어느 쪽이든 terraform-onp 정책 이상이면 통한다.
#
#   사람     vault login -method=userpass username=pneuma        (TTL 8h)
#   AppRole  vault write -field=token auth/approle/login \
#              role_id=$(terraform -chdir=../vault output -raw terraform_onp_role_id) \
#              secret_id=<사람이 발급한 값>
#
# provider 블록에 auth_login_approle 을 박지 않는 이유는 secret_id 를 변수로
# 받아야 하기 때문이다. 변수로 받으면 그 값이 tfvars 나 명령행에 남는데,
# 지금 없애려는 것이 바로 그것이다. 토큰 발급은 셸에서 하고 결과만 넘긴다.
provider "vault" {}

provider "proxmox" {
  # tfvars 가 아니라 Vault 에서 온다 — vault.tf
  endpoint  = local.proxmox_endpoint
  api_token = local.proxmox_api_token
  insecure  = var.proxmox_insecure

  # snippets(cloud-init user-data) 업로드는 API 가 아니라 SSH 로 나간다.
  # 이 블록이 없으면 proxmox_virtual_environment_file 이 실패한다.
  #
  # agent = true 는 ssh-agent 에 키가 있어야 한다는 뜻이다. 그 키는
  # scripts/cntlp-env.sh 가 Vault 에서 꺼내 `ssh-add -t` 로 넣는다 —
  # 디스크를 거치지 않는다.
  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
