# Network 루트 모듈이 S3에 저장한 output을 읽는다.
# Network가 먼저 apply되어 state가 존재해야 Vault plan/apply가 가능하다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# ── Egress state를 읽는 이유 ────────────────────────────────────
#
# **Vault는 egress 스택 없이 부트스트랩되지 않는다.**
#
# Private Subnet에 있으므로 인터넷으로 나가는 길이 NAT Gateway뿐이다.
# 그 경로가 없으면 apt 설치도, Tailscale 좌표 서버 접속도 안 된다.
# 그리고 Vault 접근 경로가 메시뿐이라, NAT가 없으면 **인스턴스는 살아 있는데
# 아무도 닿을 수 없는 상태**가 된다 — 실패로 보이지 않아 알아채기 어렵다.
#
# egress는 비용을 아끼려고 destroy하도록 설계된 스택이다
# (NAT Gateway는 시간당 과금 + 데이터 처리 요금). 그래서 그 destroy가
# Vault를 고립시킨다는 사실을 여기서 코드로 드러낸다.
# 순서와 복구 절차는 docs/runbook-vault.md 가 갖는다.
data "terraform_remote_state" "egress" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/egress/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# NAT 경로가 실제로 있는지 본다. 없으면 apply는 성공하고 부트스트랩만 실패한다.
check "egress_route_exists" {
  assert {
    condition = try(
      length(data.terraform_remote_state.egress.outputs.nat_gateway_id) > 0,
      false
    )
    error_message = join(" ", [
      "Egress state has no NAT gateway.",
      "Vault sits in a private subnet and reaches Tailscale only through NAT,",
      "so it would boot unreachable. Apply terraform/aws/egress first."
    ])
  }
}

# Canonical 공식 계정이 배포한 최신 Ubuntu 24.04 LTS AMI를 조회한다.
data "aws_ami" "ubuntu" {
  most_recent = true
  # Canonical의 공식 AWS 계정 ID
  owners = ["099720109477"]

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*",
    ]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
