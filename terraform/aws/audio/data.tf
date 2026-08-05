# Node Instance Profile 방식에서는 Audio 권한을 Compute Stack이 소유한 Worker
# Role에 붙인다. Node의 IAM 정체성은 Compute가, 자원별 권한은 각 Stack이
# 소유하는 경계를 유지한다.
data "terraform_remote_state" "compute" {
  count = var.enable_node_role_policy ? 1 : 0

  backend = "s3"

  config = {
    bucket  = "cntlp-aws-tfstate"
    key     = "aws/compute/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}
