# 상태를 로컬에 두지 않는다.
#
# 버킷과 암호화 키는 terraform 밖에서 손으로 만든다 — docs/runbook-tfstate.md
#
# 버킷 이름이 cntlp-tfstate 에서 cntlp-aws-tfstate 로 바뀌었다.
# 한때 버킷이 둘이었다 — AWS 스택 넷은 cntlp-aws-tfstate 를, gcp·onp 는
# cntlp-tfstate 를 썼다. 상태 저장소가 갈리면 "이 스택 상태가 어디 있지"가
# 스택마다 다른 답을 갖는다. 하나로 모은다.
#
# **온프렘 상태를 aws 이름의 버킷에 넣는 것이 어색해 보이지만 맞다.**
# 명명 규약의 물리 위치 토큰은 *그 자원이 어디에 사는지*를 가리킨다.
# 버킷 자체가 AWS 자원이므로 aws 가 붙는다. 안에 담긴 상태가 무엇에 대한
# 것인지는 key 가 가른다 — onp/, gcp/, aws/vault/.
terraform {
  backend "s3" {
    bucket  = "cntlp-aws-tfstate"
    key     = "onp/terraform.tfstate"
    region  = "ap-northeast-2"
    encrypt = true

    # 락이 없으면 같은 스택을 두 사람이 동시에 apply 할 때 막을 것이 없다.
    # DynamoDB 테이블 대신 S3 네이티브 락을 쓴다 — 테이블을 누가 만드느냐는
    # 닭걀 문제가 없고 dynamodb_table 은 TF 1.11 부터 deprecated 다.
    # 요구 버전: Terraform 1.10+
    use_lockfile = true
  }
}
