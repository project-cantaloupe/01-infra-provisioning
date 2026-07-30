# 온프렘 ansible 이 쓴다. tailnet 조인에 필요한 것만.
#
# **proxmox 토큰이 여기 없다.** ansible 은 VM 을 만들지 않는다 — terraform 이
# 만든 것에 붙을 뿐이다. 동적 인벤토리가 Proxmox API 를 쓰지만 그것은
# 워크스테이션에서 사람 토큰으로 돌고 이 AppRole 로 돌지 않는다.
#
# **개인키도 없다.** 개인키는 워크스테이션의 ssh-agent 로만 들어가고
# (scripts/cntlp-env.sh), 그건 사람 토큰이 하는 일이다. 원격 노드에서 도는
# ansible 자신은 개인키를 볼 이유가 없다.

path "secret/data/onp/tailscale" {
  capabilities = ["read"]
}

path "secret/data/ssh/cntlp-public" {
  capabilities = ["read"]
}

path "secret/metadata/onp/tailscale" {
  capabilities = ["read"]
}

path "secret/metadata/ssh/cntlp-public" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
