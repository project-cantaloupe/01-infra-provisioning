# 사람. 전체 읽기·쓰기.
#
# 시크릿을 넣는 것은 사람이 한다 (terraform 이 하면 값이 tfstate 에 평문으로
# 남는다). 그래서 create·update 가 필요하다.
#
# **이 정책은 root 가 아니다.** sys/ 대부분과 auth 설정 변경 권한이 없어서
# 정책을 스스로 넓힐 수 없다. 그런 변경은 terraform/vault 를 고쳐 apply 한다.

path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# KV v2 는 data/ 와 metadata/ 가 갈려 있다.
# 버전 이력 조회와 소프트 삭제가 metadata 쪽이다.
path "secret/metadata/*" {
  capabilities = ["read", "list", "delete"]
}

# 잘못 지운 버전을 되살린다. KV v2 의 소프트 삭제를 쓸 수 있게 한다.
path "secret/undelete/*" {
  capabilities = ["update"]
}

# secret_id 발급. terraform 이 만들지 않으므로 사람이 한다 — auth.tf 참고.
path "auth/approle/role/+/secret-id" {
  capabilities = ["create", "update"]
}

# role_id 조회. terraform output 으로도 보이지만 CLI 로 확인할 수 있게 둔다.
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}

# 자기 토큰 조회·갱신
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

# raft 스냅샷. 런북의 백업 절차가 쓴다.
# **스냅샷은 시크릿 전부를 담는다.** 이 권한을 AppRole 에 주지 않는 이유다.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

# seal 상태 확인. 재부팅 후 auto-unseal 이 됐는지 본다.
path "sys/seal-status" {
  capabilities = ["read"]
}

path "sys/health" {
  capabilities = ["read"]
}

# 마운트 목록 조회. UI 가 요구한다.
path "sys/mounts" {
  capabilities = ["read", "list"]
}
