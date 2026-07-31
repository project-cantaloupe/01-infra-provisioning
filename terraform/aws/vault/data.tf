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
# 순서와 복구 절차는 references/20260801_infra-05-vault-ops.md 가 갖는다.
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

# ── EICE Security Group 을 이름으로 찾는다 ──────────────────────
#
# remote_state 로 읽지 않는다. Network 스택에 output 을 추가하면 그 스택을 다시
# apply 해야 하는데, **그건 이 태스크가 감당할 위험이 아니다.**
# terraform.tfvars 가 리포에 없어서(gitignored) enable_eice·CIDR 값을 모르고,
# 값을 빠뜨린 채 apply 하면 살아 있는 EICE 를 지우려 든다.
#
# aws_security_groups(복수형)를 쓰는 이유는 **없을 때 에러가 아니라 빈 목록을
# 반환하기 때문**이다. EICE 는 enable_eice 로 켜고 끄는 한시적 자원이라
# 없는 상태가 정상적으로 존재한다. 단수형 data source 는 그때 apply 를 깨뜨린다.
data "aws_security_groups" "eice" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.network.outputs.vpc_id]
  }

  filter {
    name   = "group-name"
    values = [var.eice_security_group_name]
  }
}
