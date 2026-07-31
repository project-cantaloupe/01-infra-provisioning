# role_id 는 비밀이 아니다. 사원번호에 해당한다 — secret_id 없이는 아무것도
# 열지 못한다. 그래서 출력하고 sensitive 를 걸지 않는다.
#
# 걸면 오히려 나쁘다. 값을 꺼내려면 `output -raw` 를 써야 하고, 그 습관이
# 진짜 비밀에도 옮는다.
output "terraform_onp_role_id" {
  description = "role_id for terraform/onp; pair it with a secret_id issued by hand"
  value       = vault_approle_auth_backend_role.terraform_onp.role_id
}

output "ansible_onp_role_id" {
  description = "role_id for on-prem Ansible runs"
  value       = vault_approle_auth_backend_role.ansible_onp.role_id
}

output "kv_mount_path" {
  description = "KV v2 mount path"
  value       = vault_mount.secret.path
}

# apply 후 사람이 해야 하는 것들. terraform 이 할 수 없는 이유는 각 파일
# 주석에 있고, 요약하면 전부 "그 값이 tfstate 에 평문으로 남는다" 다.
output "next_steps" {
  description = "Manual steps after apply; Terraform cannot do these without writing secrets to state"
  value       = <<-EOT
    1. 사람 계정 (비밀번호를 stdin 으로 — 셸 히스토리에 남지 않는다)
         vault write auth/userpass/users/${var.human_username} \
           password=- policies=${var.human_username}

    2. secret_id 발급 (TTL 24시간. 만료되면 다시 발급한다)
         vault write -f auth/approle/role/terraform-onp/secret-id
         vault write -f auth/approle/role/ansible-onp/secret-id

    3. 시크릿 4개 투입
         vault kv put secret/onp/proxmox   api_token=... endpoint=...
         vault kv put secret/onp/tailscale auth_key=...
         vault kv put secret/ssh/cntlp-public  authorized_keys=@~/.ssh/cantaloupe_ed25519.pub
         vault kv put secret/ssh/cntlp-private private_key=@~/.ssh/cantaloupe_ed25519

    4. root 토큰을 버리고 사람 계정으로 다시 로그인한다
         unset VAULT_TOKEN
         vault login -method=userpass username=${var.human_username}
         vault token lookup | grep -E 'policies|ttl'

    5. 정책 경계를 확인한다 — terraform-onp 는 개인키를 읽지 못해야 한다
         ROLE_ID=$(terraform -chdir=terraform/vault output -raw terraform_onp_role_id)
         SECRET_ID=<2번에서 받은 값>
         TOKEN=$(vault write -field=token auth/approle/login \
           role_id="$ROLE_ID" secret_id="$SECRET_ID")
         VAULT_TOKEN=$TOKEN vault kv get secret/onp/proxmox          # 성공해야 한다
         VAULT_TOKEN=$TOKEN vault kv get secret/ssh/cntlp-private    # 403 이어야 한다

    자세한 절차는 docs/runbook-vault.md 를 본다.
  EOT
}
