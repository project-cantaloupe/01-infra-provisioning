# 정책 HCL 을 heredoc 이 아니라 별도 파일로 둔다. heredoc 에 넣으면 편집기의
# HCL 문법 지원이 안 되고, 정책이 길어지면 어디가 정책이고 어디가 terraform
# 인지 안 보인다. 정책은 리뷰에서 가장 자세히 봐야 하는 부분이다.

# ⚠️ **이름이 `pneuma` 가 아니라 `human` 이다** (2026-08-11 변경).
#
# userpass 시절에는 정책이 계정 하나에 붙어 있어서 사람 이름이 곧 정책
# 이름이었다. 지금은 OIDC **그룹**이 이 정책을 받는다 — `secops` 그룹이
# `pneuma` 라는 이름의 정책을 갖는 것은 읽는 사람을 속인다.
#
# 정책 이름은 **누가 받는가**가 아니라 **무엇을 할 수 있는가**를 적는다.
resource "vault_policy" "human" {
  name   = "human"
  policy = file("${path.module}/policies/human.hcl")
}

resource "vault_policy" "terraform_onp" {
  name   = "terraform-onp"
  policy = file("${path.module}/policies/terraform-onp.hcl")
}

resource "vault_policy" "ansible_onp" {
  name   = "ansible-onp"
  policy = file("${path.module}/policies/ansible-onp.hcl")
}

resource "vault_policy" "eso_harbor" {
  name   = "eso-harbor"
  policy = file("${path.module}/policies/eso-harbor.hcl")
}
