# Network 루트 모듈이 S3에 저장한 output을 읽는다.
# Network가 먼저 apply되어 state가 존재해야 Compute plan/apply가 가능하다.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# Canonical 공식 계정이 배포한 최신 Ubuntu 24.04 LTS AMI를 조회한다.
# data 블록은 새 AMI를 생성하지 않고 AWS에 이미 존재하는 AMI를 검색한다.
data "aws_ami" "ubuntu" {
  most_recent = true
  # Canonical의 공식 AWS 계정 ID
  owners = ["099720109477"]

  # Ubuntu 24.04 Noble, gp3 기반 서버 이미지
  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*",
    ]
  }

  # t3.small에서 사용할 x86_64 아키텍처
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  # HVM 가상화와 EBS Root Device 이미지만 선택한다.
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
