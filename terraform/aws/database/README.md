# AWS Database

애플리케이션이 공용으로 사용할 PostgreSQL RDS 인스턴스 한 대를 관리한다.
데이터베이스 서버와 최초 `audio` 데이터베이스까지만 만들며, 테이블과 스키마
마이그레이션은 애플리케이션 저장소에서 관리한다.

## 생성 자원

- Private Single-AZ PostgreSQL RDS `cntlp-aws-api-db`
- 서로 다른 두 AZ의 Private Subnet을 사용하는 DB Subnet Group
- AWS Kubernetes Worker Security Group에서 오는 TCP 5432만 허용하는 DB Security Group
- RDS가 Secrets Manager에서 자동 관리하는 Master 비밀번호
- 7일 자동 백업과 삭제 시 최종 Snapshot

RDS는 Public IP를 받지 않는다. 현재 Security Group 계약에서는 AWS Worker만
직접 접근할 수 있다. GCP·On-Prem Worker의 직접 접근은 Tailscale 에이전트만으로
해결되지 않으며, VPC와 각 네트워크 사이의 별도 라우팅 설계가 필요하다.

## 적용 순서

먼저 `terraform/aws/network/terraform.tfvars`에 다음 두 값을 추가하고 Network를
적용한다.

```hcl
database_availability_zone   = "ap-northeast-2c"
database_private_subnet_cidr = "10.20.20.0/24"
```

```bash
export AWS_PROFILE=cntlp

terraform -chdir=terraform/aws/network init -reconfigure
terraform -chdir=terraform/aws/network validate
terraform -chdir=terraform/aws/network plan -out=network.tfplan
terraform -chdir=terraform/aws/network apply network.tfplan

cp terraform/aws/database/terraform.tfvars.example \
  terraform/aws/database/terraform.tfvars
# 실제 계정 ID와 태그 값을 terraform.tfvars에 입력한다.

terraform -chdir=terraform/aws/database init -reconfigure
terraform -chdir=terraform/aws/database validate
terraform -chdir=terraform/aws/database plan -out=database.tfplan
terraform -chdir=terraform/aws/database apply database.tfplan
```

`terraform.tfvars`와 `*.tfplan`은 Git에 커밋하지 않는다. `plan`에서는 Network의
기존 VPC·Subnet·노드가 교체되지 않고 Database용 Subnet 하나만 추가되는지 먼저
확인한다.

## 접속 정보 확인

```bash
terraform -chdir=terraform/aws/database output database_address
terraform -chdir=terraform/aws/database output database_port
terraform -chdir=terraform/aws/database output master_username

SECRET_ARN=$(terraform -chdir=terraform/aws/database output -raw master_user_secret_arn)
AWS_PROFILE=cntlp aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text
```

마지막 명령은 비밀번호를 터미널에 출력한다. 출력값을 문서, Git, Terraform 변수,
Kubernetes manifest에 직접 저장하지 않는다. 실제 애플리케이션 연결 시에는
Kubernetes Secret 연동 방식을 별도로 구성한다.

## 비용과 삭제 경계

비용은 RDS 인스턴스 실행 시간, gp3 스토리지, 백업·Snapshot 저장량,
Secrets Manager Secret에서 발생한다. NAT Gateway는 RDS 생성에 필요하지 않다.

Database 상태는 Compute 상태와 분리되어 있으므로 EC2를 삭제해도 RDS는 유지된다.
Network를 삭제하기 전에는 Database를 먼저 삭제해야 한다. 기본
`deletion_protection = true`이므로 의도적으로 삭제할 때는 다음 순서를 따른다.

1. `terraform.tfvars`의 `deletion_protection`을 `false`로 바꾼다.
2. `terraform plan`과 `terraform apply`로 삭제 보호 해제를 먼저 반영한다.
3. `terraform destroy`를 실행하고 최종 Snapshot 생성을 확인한다.

같은 이름의 `cntlp-aws-api-db-final` Snapshot이 이미 남아 있으면 다음 삭제 전에
기존 Snapshot의 보관 또는 삭제 여부를 먼저 결정해야 한다.
