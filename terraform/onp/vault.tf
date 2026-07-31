# Proxmox 접속 정보와 SSH 공개키를 Vault 에서 읽는다. tfvars 에 두지 않는다.
#
# ── 토큰은 ephemeral, 공개키는 data ─────────────────────────────
#
# 둘을 다르게 읽는 것이 이 파일의 요점이다.
#
# **data source 의 결과는 tfstate 에 평문으로 들어간다.** sensitive = true 는
# 화면 출력만 가리고 state 는 가리지 않는다. 이 리포는 그 사실을 이미 알고
# 있다 — .gitignore 가 "실제로 이 리포의 tfplan 에서 proxmox_api_token 이
# 평문으로 나왔다" 고 적어뒀다.
#
# **ephemeral 자원은 state 에도 plan 에도 저장되지 않는다.** 값이 apply 도중에만
# 존재하고 끝나면 버려진다. Terraform 1.10 부터고 이 리포는 1.10 이상을 요구한다
# (versions.tf). vault provider 5.10 이 data source 쪽을 deprecated 로 표시하고
# 이쪽을 권한다.
#
# 그래서 Proxmox 토큰은 ephemeral 로 읽는다. **006 스펙 5절이 "달성 불가능"이라고
# 적은 것이 달성 가능해졌다** — 그 판단은 data source 밖에 없다는 전제였다.
# 검증 기준 8번의 원문("tfstate 를 grep 했을 때 토큰이 나오지 않는다")이
# 이제 실제로 성립한다.
#
# 공개키는 ephemeral 로 못 읽는다. ephemeral 값은 provider 설정과 다른 ephemeral
# 자원에만 흘릴 수 있고 일반 자원의 인자로는 못 간다. 공개키는 cloud-init
# 템플릿을 거쳐 proxmox_virtual_environment_file 에 들어가야 하므로 data 다.
# **공개키는 비밀이 아니므로 state 에 남아도 된다.**
#
# ── S3 백엔드와 짝인 이유는 그대로다 ────────────────────────────
#
# 토큰이 안 들어가도 state 에는 여전히 인프라 구조가 통째로 담긴다.
# 상태는 cntlp-aws-tfstate 에 있고 그 버킷의 기본 암호화는 aws:kms 다
# (alias/cntlp-aws-tfstate) → docs/06_tfstate.md
#
# ── 폴백이 없다 ─────────────────────────────────────────────────
#
# Vault 가 안 닿으면 plan 이 그냥 죽는다. tfvars 로 조용히 돌아가지 않는다.
# 폴백을 남기면 사람은 결국 쉬운 길로 가고, 이 작업이 없애려는 상태가
# 그대로 남는다 → tasks/done/006_vault-setup.md 8절

ephemeral "vault_kv_secret_v2" "proxmox" {
  mount = "secret"
  name  = "onp/proxmox"
}

# **개인키(secret/ssh/cntlp-private)는 여기서 읽지 않는다.** 읽을 수도 없다 —
# terraform-onp 정책에 그 경로가 없어서 403 이 난다.
#
# KV v2 에는 필드 단위 ACL 이 없어서 공개키와 개인키를 다른 경로로 갈랐다.
# 한 경로에 뭉쳐 뒀으면 cloud-init 에 넣을 공개키를 읽는 이 스택이 개인키까지
# 읽고, 그러면 VM 을 만들 권한이 모든 노드에 root 로 들어갈 권한이 된다
# → 같은 문서 2절
data "vault_kv_secret_v2" "ssh_public" {
  mount = "secret"
  name  = "ssh/cntlp-public"
}

locals {
  # ephemeral 값을 참조하므로 이 둘도 ephemeral 이다. provider 설정 외의
  # 곳에 쓰면 terraform 이 막는다 — 실수로 state 에 새는 경로가 없다.
  proxmox_endpoint  = ephemeral.vault_kv_secret_v2.proxmox.data["endpoint"]
  proxmox_api_token = ephemeral.vault_kv_secret_v2.proxmox.data["api_token"]

  # KV 에는 .pub 파일 내용이 그대로 들어 있다. 한 줄이 키 하나다.
  # cloud-init 템플릿이 목록을 요구하므로 줄 단위로 가른다. compact 는
  # 파일 끝 빈 줄이 빈 문자열 항목으로 남는 것을 막는다 — 그게 남으면
  # authorized_keys 에 빈 줄이 들어가고 sshd 가 조용히 무시한다.
  ssh_public_keys = compact(
    split("\n", trimspace(data.vault_kv_secret_v2.ssh_public.data["authorized_keys"]))
  )
}

# 공개키가 실제로 들어왔는지 plan 시점에 본다.
#
# Vault 에 경로는 있는데 필드 이름이 다르면 조회는 성공하고 값만 null 이 된다.
# 그대로 apply 하면 **로그인할 수 없는 VM** 이 만들어지고, 그 실패는 VM 이 뜬
# 뒤 ansible 단계에서야 "Permission denied (publickey)" 로 나타난다.
#
# Proxmox 쪽 값에는 같은 검사를 걸지 않는다. ephemeral 값은 check 블록에
# 참조할 수 없다 — 그쪽이 비면 provider 가 401 로 죽고, 그때는
# `vault kv get secret/onp/proxmox` 로 필드 이름을 확인한다.
check "ssh_public_key_present" {
  assert {
    condition     = length(local.ssh_public_keys) > 0
    error_message = "secret/ssh/cntlp-public 의 authorized_keys 가 비어 있다. 이대로 apply 하면 로그인할 수 없는 VM 이 만들어진다."
  }
}
