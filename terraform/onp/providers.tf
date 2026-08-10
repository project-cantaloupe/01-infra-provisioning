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
provider "vault" {
  # **자식 토큰을 만들지 않는다.**
  #
  # provider 는 기본적으로 실행마다 auth/token/create 로 짧은 수명의 자식
  # 토큰을 발급해 쓰고 끝나면 폐기한다. 이 프로젝트의 정책에는 그 권한이
  # 없어서 plan 이 이렇게 죽는다:
  #
  #   Error: Error Configuring Resource Client
  #   failed to create limited child token: ... Code: 403 permission denied
  #
  # 권한을 주는 대신 기능을 끈다. 자식 토큰은 부모 정책을 넘지 못하므로
  # auth/token/create 가 권한 상승은 아니지만, 정책을 넓히지 않고 끝나는
  # 길이 있으면 그쪽이 낫다 — terraform-onp 정책이 좁다는 것 자체가
  # 이 설계의 주장이다 (006 2절).
  #
  # 잃는 것은 "20분짜리 토큰으로 좁히기" 다. 여기 오는 토큰은 이미 짧고
  # 좁다 — 사람 8h, AppRole 1h. 그리고 자식 토큰을 안 만들면 provider 가
  # 토큰 수명에 손대지 않으므로, 사람이 로그인한 세션이 terraform 실행
  # 끝에 끊기지도 않는다.
  skip_child_token = true
}

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
