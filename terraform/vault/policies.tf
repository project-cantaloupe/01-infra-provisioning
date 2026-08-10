# 정책 HCL 을 heredoc 이 아니라 별도 파일로 둔다. heredoc 에 넣으면 편집기의
# HCL 문법 지원이 안 되고, 정책이 길어지면 어디가 정책이고 어디가 terraform
# 인지 안 보인다. 정책은 리뷰에서 가장 자세히 봐야 하는 부분이다.

resource "vault_policy" "human" {
  name   = var.human_username
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
