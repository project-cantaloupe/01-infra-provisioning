# AWS Karpenter Foundation

Self-managed Kubernetes에서 Karpenter를 검증하기 위한 AWS 기반 자원을 관리한다.
현재 단계는 Golden Image를 만드는 임시 Packer Builder의 IAM과 네트워크만 만든다.
Karpenter Controller 권한과 동적 Worker Node 권한은 별도 단계에서 추가한다.

## 현재 생성 자원

- Packer Builder 전용 IAM Role과 Instance Profile
- SSM managed instance 및 Session Manager 연결 최소 inline 권한
- inbound 없이 outbound만 허용하는 Packer Builder Security Group
- 기본값은 꺼져 있는 Golden AMI Boot Test EC2

기본 상태에는 시간당 과금 자원이 없다. `packer build`를 실행할 때는
임시 `t3.small` EC2와 30 GiB gp3가 생성되고, Boot Test를 켜면 검증하는
동안 동일한 사양의 EC2와 Root EBS 비용이 발생한다. 성공한 AMI의 EBS
Snapshot 저장 비용은 계속 발생한다.

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

## Golden AMI Boot Test

Karpenter Controller를 설치하기 전에 완성 AMI가 새 EC2의 초기 부팅을
완료하는지 분리해 검증한다. 테스트는 Private Subnet에 `t3.small` 한 대만
만들고 Public IP와 inbound 규칙을 추가하지 않는다. Packer Builder와 동일한
SSM Instance Profile과 Security Group을 재사용한다.

```bash
terraform -chdir=terraform/aws/karpenter plan \
  -var='enable_boot_test=true' \
  -var='boot_test_ami_name=cntlp-aws-cicd-k8s-worker-abcdef0' \
  -var='boot_test_expires_on=2099-12-31'
```

이 단계에서는 Tailscale auth key와 kubeadm join token을 주입하지 않는다.
`cloud-init`, machine-id, SSH host key, containerd, kubelet, tailscaled와 기존 Node 상태
미포함만 확인한다. 임시 호스트명은 Node 명명 규칙의 예약 번호인
`cntlp-aws-wk-99`를 사용한다.

EC2 상태 검사와 SSM Agent `Online`을 확인한 뒤 저장소에 남긴 검증
스크립트를 실행한다.

```bash
AWS_PROFILE=cntlp \
  terraform/aws/karpenter/scripts/verify-boot-test.sh
```

스크립트는 SSM Run Command로 읽기 전용 검증을 수행한다. 첫 부팅에서
`/etc/cni/net.d`가 빈 디렉터리로 다시 생성될 수 있으므로, 디렉터리 존재가
아니라 CNI 설정 파일이 0개인지 확인한다.

검증이 끝나면 `enable_boot_test` 인자 없이 다시 plan·apply해 해당
EC2와 Root EBS를 삭제한다. AMI와 Snapshot, Packer Builder IAM·Security Group은
삭제하지 않는다.

## 삭제 경계

```bash
terraform -chdir=terraform/aws/karpenter destroy
```

이 명령은 Boot Test EC2가 남아 있으면 함께 삭제한 뒤 Packer Builder용
IAM과 Security Group을 삭제한다. Packer가 만든 AMI와 EBS Snapshot,
기존 EC2, VPC, Kubernetes Node는 삭제하지 않는다.
