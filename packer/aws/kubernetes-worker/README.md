# AWS Kubernetes Worker Golden Image

Karpenter가 생성할 Worker의 공통 OS와 패키지를 AMI에 미리 설치한다.
이미지에는 Kubernetes 클러스터 가입 정보와 Tailscale 장치 신원을 넣지 않는다.

## 포함 항목

- Ubuntu 24.04 LTS
- containerd와 systemd cgroup 설정
- kubelet, kubeadm, kubectl v1.36.3
- Kubernetes 커널 모듈, sysctl, swap 비활성화
- Tailscale 에이전트와 노드 방화벽
- AWS CLI v2 2.36.18
- kubelet ECR credential provider와 SHA-256 고정 설정
- Secret 값을 포함하지 않는 Worker bootstrap 실행기

## 포함하지 않는 항목

- Tailscale OAuth Client Secret과 machine key
- kubeadm join token과 kubelet 인증서
- CNI 상태와 Kubernetes Node 이름
- 애플리케이션 이미지와 AWS 자격증명

노드별 값은 EC2 부팅 시 user data에서 주입한다. AMI 하나를 여러 노드가
공유하더라도 machine-id, SSH host key, Tailscale 신원은 각각 새로 생성된다.

## 사전 조건

저장소 루트에서 실행한다. Packer 1.14 이상, AWS CLI, Session Manager Plugin,
Ansible 가상환경이 필요하다. Packer는 Private Subnet에서 임시 EC2를 만들고
SSM 터널로만 접속하므로 Public IP와 SSH ingress를 만들지 않는다.

```bash
terraform -chdir=terraform/aws/karpenter init -reconfigure
terraform -chdir=terraform/aws/karpenter plan
terraform -chdir=terraform/aws/karpenter apply

terraform -chdir=terraform/aws/karpenter output
cp packer/aws/kubernetes-worker/worker.pkrvars.hcl.example \
  packer/aws/kubernetes-worker/worker.pkrvars.hcl
```

`worker.pkrvars.hcl`의 ID와 `build_id`, `expires_on`을 실제 값으로 바꾼다.
`build_id`는 날짜나 `v2` 대신 해당 이미지 코드를 가리키는 짧은 Git commit SHA를
사용한다. 실제 변수 파일과 빌드 manifest는 Git에서 제외된다.

## 정적 검증과 빌드

```bash
packer init packer/aws/kubernetes-worker
packer fmt -check packer/aws/kubernetes-worker
packer validate \
  -var-file=packer/aws/kubernetes-worker/worker.pkrvars.hcl \
  packer/aws/kubernetes-worker

packer build \
  -var-file=packer/aws/kubernetes-worker/worker.pkrvars.hcl \
  packer/aws/kubernetes-worker
```

`validate`는 AWS 리소스를 만들지 않는다. `build`는 임시 `t3.small` EC2와 30 GiB
gp3를 사용한 뒤 EC2를 종료하고, AMI와 EBS Snapshot을 남긴다. 빌드 실패 시에도
EC2와 EBS가 남지 않았는지 태그 `Name=cntlp-aws-cicd-packer-builder`로 확인한다.

Boot Test는 provider 바이너리·버전·설정 파일을 확인한다. 자동 가입 검증에서는
실행 중인 kubelet의 `kubeadm-flags.env`에 두 credential-provider 인자가 모두
있는지도 확인한다. 최종 ECR 검증은 실제 private Audio image Pod가
`ImagePullBackOff` 없이 Ready가 되는 것으로 완료한다.

## 삭제 경계

더 이상 사용하지 않는 AMI는 먼저 Karpenter 설정에서 참조를 제거한 뒤 AMI를
deregister하고 연결된 Snapshot을 별도로 삭제한다. Terraform destroy는 빌더용
IAM Role, Instance Profile, Security Group만 삭제하며 AMI와 Snapshot은 삭제하지
않는다.
