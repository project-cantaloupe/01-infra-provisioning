# AWS Karpenter Foundation

Self-managed Kubernetes에서 Karpenter를 검증하기 위한 AWS 기반 자원을 관리한다.
Golden Image Builder와 자동 가입 Secret, Karpenter Controller의 AWS 최소 권한을
기존 Network·Compute 상태와 분리해 관리한다.

## 현재 생성 자원

- Packer Builder 전용 IAM Role과 Instance Profile
- SSM managed instance 및 Session Manager 연결 최소 inline 권한
- inbound 없이 outbound만 허용하는 Packer Builder Security Group
- 기본값은 꺼져 있는 Golden AMI Boot Test EC2
- 기본값은 꺼져 있는 자동 가입용 Secret 컨테이너와 Worker 최소 조회 권한
- 기본값은 꺼져 있는 Karpenter Controller EC2 lifecycle 최소 권한

기본 상태에는 시간당 과금 자원이 없다. `packer build`를 실행할 때는
임시 `t3.small` EC2와 30 GiB gp3가 생성되고, Boot Test를 켜면 검증하는
동안 동일한 사양의 EC2와 Root EBS 비용이 발생한다. 성공한 AMI의 EBS
Snapshot 저장 비용은 계속 발생한다.

Karpenter Controller는 Self-managed Kubernetes라 IRSA나 EKS Pod Identity를
사용하지 못한다. `enable_controller_foundation=true`일 때만 기존 Control Plane
Instance Profile에 정책을 붙이며, Controller Pod는 Control Plane Node에 고정한다.
정책은 Karpenter 소유 태그가 붙은 EC2와 Launch Template만 삭제할 수 있고 기존
Service Worker Role만 EC2에 전달할 수 있다.

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

## Karpenter Controller 기반

Karpenter `1.14.0`은 Kubernetes `1.36`을 지원한다. Controller를 설치하기 전
아래 계획에서 기존 Control Plane Role에 inline Policy 하나만 추가되는지
확인한다.

```bash
terraform -chdir=terraform/aws/karpenter plan \
  -var='enable_controller_foundation=true'
```

이 단계는 EC2, SQS, EKS 자원을 만들지 않는다. 검증용 NodePool은 기존 Worker
Instance Profile, Private Subnet, Worker Security Group과 정확한 Golden AMI를
재사용한다. Kubernetes Controller와 NodePool 매니페스트는
`02-k8s-manifests` 저장소가 관리한다.

초기 E2E는 `cntlp-aws-wk-99` 한 대만 허용한다. 이 고정 이름은 Karpenter가
EC2를 생성·가입·삭제하는 경로를 검증하기 위한 예약 이름이며 다중 NodePool
운영 계약이 아니다. 다중 노드 전환 전에는 고유한 두 자리 Node 번호 할당과
Tailscale auth key·kubeadm token 회전 방식을 별도로 확정해야 한다.

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

## Tailscale과 kubeadm 자동 가입 검증

기본 Boot Test가 성공한 다음, 같은 예약 이름 `cntlp-aws-wk-99` 한 대로
Tailscale 가입과 kubeadm join을 검증한다. 이 단계는 Karpenter Controller나
다중 Node 명명 로직을 검증하지 않는다.

Terraform은 Secret 컨테이너와 해당 Secret 하나를 읽는 Worker IAM 권한만
관리한다. Tailscale auth key와 kubeadm bootstrap token 값은 Terraform 변수,
state, EC2 user data에 넣지 않는다. 기존 Compute state가 아직 Instance Profile
전용 output을 갖지 않아도, 현재 계약상 Worker Role과 Instance Profile 이름이
같으므로 파괴적인 Compute apply 없이 기존 output을 사용할 수 있다.

```bash
terraform -chdir=terraform/aws/karpenter plan \
  -var='enable_bootstrap_foundation=true' \
  -var='bootstrap_expires_on=2099-12-31'
```

계획에는 Secrets Manager Secret 하나와 기존 Service Worker Role에 붙는
`secretsmanager:GetSecretValue` inline Policy 하나만 있어야 한다. 승인 후
apply한 다음, 태그가 허용된 단기·ephemeral Tailscale auth key를 준비하고
아래 스크립트를 실행한다. 키는 화면에 표시하거나 shell history에 넣지 않는다.

```bash
AWS_PROFILE=cntlp \
  terraform/aws/karpenter/scripts/prepare-bootstrap-secret.sh
```

스크립트는 Control Plane에서 TTL 30분 kubeadm token을 새로 만들고 Secret
값을 AWS CLI로 직접 등록한다. 그다음 Golden AMI 이름을 지정해 자동 가입
Boot Test를 계획한다.

```bash
terraform -chdir=terraform/aws/karpenter plan \
  -var='enable_boot_test=true' \
  -var='enable_bootstrap_foundation=true' \
  -var='boot_test_join_cluster=true' \
  -var='boot_test_ami_name=cntlp-aws-cicd-k8s-worker-abcdef0' \
  -var='boot_test_expires_on=2099-12-31' \
  -var='bootstrap_expires_on=2099-12-31'
```

apply 후 자동 가입 결과는 다음 스크립트로 확인한다.

```bash
terraform/aws/karpenter/scripts/verify-automatic-join.sh
```

검증이 끝나면 cleanup 스크립트로 Node를 drain·delete하고 Tailscale에서
logout하며 kubeadm token을 명시적으로 삭제한다.

```bash
AWS_PROFILE=cntlp \
  terraform/aws/karpenter/scripts/cleanup-automatic-join.sh
```

그다음 모든 enable 인자 없이 karpenter Stack을 plan·apply해 Boot Test EC2,
Root EBS, 임시 Secret과 inline Policy를 제거한다. cleanup 스크립트가 token을
삭제하지 못해도 TTL 30분 뒤 자동 만료된다.

## 삭제 경계

```bash
terraform -chdir=terraform/aws/karpenter destroy
```

이 명령은 Boot Test EC2가 남아 있으면 함께 삭제한 뒤 Packer Builder용
IAM과 Security Group, bootstrap Secret과 inline Policy를 삭제한다. Packer가 만든 AMI와 EBS Snapshot,
기존 EC2, VPC, Kubernetes Node는 삭제하지 않는다.
