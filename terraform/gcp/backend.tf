# 상태를 로컬에 두지 않는다.
terraform {
  backend "s3" {
    bucket  = "cantaloupe-tfstate"
    key     = "gcp/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true
  }
}
