data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/network/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

# Canonical official Ubuntu 24.04 LTS AMI.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

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
