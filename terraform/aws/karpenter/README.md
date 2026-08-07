# AWS Karpenter Foundation

Self-managed Kubernetes에서 Karpenter를 검증하기 위한 AWS 기반 자원을 관리한다.
현재 단계는 Golden Image를 만드는 임시 Packer Builder의 IAM과 네트워크만 만든다.
Karpenter Controller 권한과 동적 Worker Node 권한은 별도 단계에서 추가한다.

## 현재 생성 자원

- Packer Builder 전용 IAM Role과 Instance Profile
- SSM managed instance 및 Session Manager 연결 최소 inline 권한
- inbound 없이 outbound만 허용하는 Packer Builder Security Group

이 Terraform Stack 자체에는 시간당 과금 자원이 없다. `packer build`를 실행할 때만
임시 `t3.small` EC2와 30 GiB gp3가 생성되며, 성공하면 AMI Snapshot 저장 비용이
계속 발생한다.

## 검증과 적용

```bash
cp terraform/aws/karpenter/terraform.tfvars.example \
  terraform/aws/karpenter/terraform.tfvars

terraform -chdir=terraform/aws/karpenter init -reconfigure
terraform -chdir=terraform/aws/karpenter fmt -check
terraform -chdir=terraform/aws/karpenter validate
terraform -chdir=terraform/aws/karpenter test
terraform -chdir=terraform/aws/karpenter plan
```

`plan`에서 IAM, Instance Profile, Security Group 이외의 자원이 없는지 확인한 뒤
apply한다. Golden Image 빌드는
[`packer/aws/kubernetes-worker/README.md`](../../../packer/aws/kubernetes-worker/README.md)를
따른다.

## 삭제 경계

```bash
terraform -chdir=terraform/aws/karpenter destroy
```

이 명령은 Packer Builder용 IAM과 Security Group만 삭제한다. Packer가 만든 AMI와
EBS Snapshot, 기존 EC2, VPC, Kubernetes Node는 삭제하지 않는다.
