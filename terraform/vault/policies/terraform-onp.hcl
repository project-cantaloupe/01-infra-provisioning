# terraform/onp 스택이 쓴다. Proxmox 에 VM 을 만들 때 필요한 것만.
#
# **secret/ssh/cntlp-private 가 여기 없는 것이 이 정책의 요점이다.**
#
# KV v2 에는 필드 단위 ACL 이 없다 — 한 경로를 읽을 수 있으면 그 안의 모든
# 필드를 읽는다. 그래서 공개키와 개인키를 다른 경로로 갈랐다. 한 경로에
# 뭉쳐 두면 cloud-init 에 넣을 공개키를 읽는 이 주체가 개인키까지 읽고,
# 그러면 **VM 을 만들 권한이 모든 노드에 root 로 들어갈 권한이 된다.**
# → tasks/doing/006_vault-setup.md 2절

path "secret/data/onp/proxmox" {
  capabilities = ["read"]
}

path "secret/data/ssh/cntlp-public" {
  capabilities = ["read"]
}

# provider 가 KV 버전을 확인하려고 metadata 를 읽는다.
# 이게 없으면 "unsupported path" 로 죽는데 원인이 권한이라는 게 잘 안 드러난다.
path "secret/metadata/onp/proxmox" {
  capabilities = ["read"]
}

path "secret/metadata/ssh/cntlp-public" {
  capabilities = ["read"]
}

# 토큰 수명 확인. 만료된 토큰으로 apply 하다 중간에 죽는 것을 미리 가른다.
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
