# Ansible Kubernetes 구성

Terraform으로 VM과 네트워크를 만든 뒤 **사람이 별도로 실행**하는 Kubernetes
구성 자동화다. Terraform의 `apply`가 Ansible을 호출하지 않는다.

AWS 동적 인벤토리는 실행 중인 EC2 중 다음 태그가 있는 Kubernetes 노드만
찾고, EICE 터널로 SSH 접속한다. `role`이 없거나 다른 값을 가진 EC2는
`platform_aws` 그룹에 들어오지 않는다.

| 태그 | 값 |
|---|---|
| `org` | `cntlp` |
| `platform` | `aws` |
| `role` | `control-plane` 또는 `service` |

기존 AWS Worker의 `role=worker` 태그는 Terraform 태그 정리가 적용될 때까지만
호환 값으로 읽고, Ansible에서는 `service` 역할로 해석한다. 신규·목표 값에는
`worker`를 사용하지 않는다.

## 자동화 범위

| 역할 | 수행 내용 |
|---|---|
| `common` | swap 영구 비활성화, 커널 모듈과 sysctl 설정 |
| `security-hardening` | SSH 보안, UFW, Tailscale-Calico 재귀 루프 차단 |
| `vpn-mesh` | Tailscale 설치·가입, MagicDNS Split DNS와 노드 IPv4 설정 |
| `tailscale-serve` | Argo CD NodePort를 MagicDNS HTTPS로 연결 |
| `containerd` | containerd 설치, `SystemdCgroup=true` 설정 |
| `kubeadm-common` | kubelet·kubeadm·kubectl 버전 고정 및 hold |
| `kubeadm-control-plane` | 단일 Control Plane 초기화와 필수 노드 라벨 적용 |
| `cni-calico` | Tigera Operator와 Calico VXLAN 네트워크 설치 |
| `kubeadm-worker` | 단기 토큰 생성, Worker 가입, 토큰 폐기와 라벨 적용 |
| `site-node-labels` | 수동 join 노드까지 필수 라벨과 providerID 계약 검증 |
| `karpenter-image` | AMI 캡처 전 kubeadm·Tailscale·machine-id·SSH host key 정리 |

클러스터 이름은 `cntlp-k8s`이고 Kubernetes API와 각 노드의
`InternalIP`에는 Tailscale IPv4를 사용한다. 플랫폼 구분은 노드 이름과
`platform` 라벨에만 남기며 AWS Worker에는 `role=service`를 적용한다. 모든 Node는
추가로 `topology.kubernetes.io/region`과
`node.kubernetes.io/instance-type`을 가져야 한다. AWS/GCP의 `spec.providerID`는
가격 키가 아니라 실제 VM 신원 검증에 사용한다.

## 재실행 안전성

- `/etc/kubernetes/admin.conf`가 있으면 `kubeadm init`을 다시 실행하지 않는다.
- `/etc/kubernetes/kubelet.conf`가 있으면 Worker를 다시 join하지 않는다.
- 이미 tailnet에 가입한 노드는 `tailscale up`을 다시 실행하지 않는다.
- 이미 가입한 노드의 MagicDNS 수용 설정은 `tailscale set`으로 필요한 경우만 갱신한다.
- 기존 수동 구축 Worker에 `--node-ip` 영구 설정이 없으면 한 번 보완하고
  kubelet을 재시작한다.
- 정상 재구성 과정에서는 `kubeadm reset`을 실행하지 않는다.

따라서 현재 클러스터에 다시 실행할 수 있지만, 클러스터 버전·Pod CIDR·CNI
같은 불변에 가까운 값의 변경은 일반 재실행이 아니라 별도 업그레이드 절차로
다뤄야 한다.

## 로컬 준비

`ansible-core 2.19`의 컨트롤 노드는 Python 3.11~3.13이 필요하다.

```bash
cd /Users/kh/Github/cantaloupe/01-infra-provisioning/ansible

python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p .collections
```

## 실행 전 환경변수

```bash
cd /Users/kh/Github/cantaloupe/01-infra-provisioning/ansible
source .venv/bin/activate

export AWS_PROFILE=cntlp
export CNTLP_SSH_PRIVATE_KEY="$HOME/.ssh/id_ed25519"
```

이미 모든 노드가 올바른 tailnet에 가입했다면 인증 키는 필요 없다. 새 노드를
처음 가입시킬 때만 재사용 가능하고 사전 승인된 Tailscale auth key를 셸
환경변수로 전달한다.

```bash
export CNTLP_TAILSCALE_AUTH_KEY='Tailscale에서 발급받은 키'
```

키는 Ansible 변수 파일, Terraform 변수, Git에 저장하지 않는다. 실행 후에는
`unset CNTLP_TAILSCALE_AUTH_KEY`로 현재 셸에서도 제거한다.

## AWS 노드 자동 실행

먼저 인벤토리와 SSH를 확인한 뒤 통합 플레이북을 실행한다.
기본 인벤토리는 On-Prem이므로 AWS 명령에는 `-i`를 생략하지 않는다.

```bash
ansible-inventory -i inventories/aws/aws_ec2.yaml --graph
ansible -i inventories/aws/aws_ec2.yaml platform_aws -m ansible.builtin.ping

ansible-playbook -i inventories/aws/aws_ec2.yaml \
  playbooks/site-cluster.yaml --syntax-check
ansible-playbook -i inventories/aws/aws_ec2.yaml \
  playbooks/site-cluster.yaml

unset CNTLP_TAILSCALE_AUTH_KEY
```

`site-cluster.yaml`의 실행 순서는 다음과 같다.

1. 전체 노드 OS·Tailscale·containerd·Kubernetes 패키지 준비
2. 단일 Control Plane 구성
3. Calico CNI 구성
4. 모든 Worker 가입
5. 클러스터 전체 노드의 `platform`/`role` 라벨 보정
6. 노드 Ready, Tailscale InternalIP, 필수 라벨 검증

Golden Image는 일반 클러스터 구성과 분리한다. Packer가 임시 EC2에
`site-golden-image.yaml`을 실행하며 Tailscale은 설치만 하고 가입하지 않는다.
빌드와 비용·삭제 경계는
[`packer/aws/kubernetes-worker/README.md`](../packer/aws/kubernetes-worker/README.md)를
따른다.

## 단계별 실행

문제가 생긴 단계를 구분하거나 구축 과정을 확인하려면 같은 순서로 하나씩
실행한다.

```bash
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-prerequisites.yaml
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-control-plane.yaml
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-cni.yaml
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-workers.yaml
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-node-labels.yaml
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-verify.yaml
```

마지막 검증 플레이북은 클러스터 설정을 변경하지 않는다. 언제든 다음 명령으로
현재 상태만 다시 확인할 수 있다.

```bash
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-verify.yaml
```

현재 수동 iptables로 넣은 Tailscale-Calico 루프 차단 규칙을 UFW에 영구
등록할 때는 전체 사전 준비 대신 보안 역할만 제한 실행할 수 있다.

```bash
ansible-playbook -i inventories/aws/aws_ec2.yaml \
  playbooks/site-prerequisites.yaml \
  --tags security \
  --limit platform_aws
```

## GCP와 On-Prem Worker

GCP와 On-Prem도 동적 인벤토리를 사용한다. GCP VM에는 Terraform이
`platform=gcp`와 `role=monitoring|logging`을, Proxmox VM에는
`platform-onp`와 `role-devops`를 부여한다. 접속 정보나 고정 IP를 정적
`hosts.ini`에 복사하지 않는다.

동적 인벤토리는 공급자 API의 실제 region/machine type을 Ansible 변수로 전달한다.
On-prem은 Terraform이 CPU/Memory 입력으로 `custom-<vCPU>vcpu-<GiB>gib` 태그를
생성한다. kubeadm 역할은 다음 Node 계약을 적용한다.

```text
platform + role + topology.kubernetes.io/region
+ node.kubernetes.io/instance-type + cloud spec.providerID
```

## Argo CD MagicDNS 접속

Argo CD를 먼저 배포한 뒤 On-Prem 노드에서 Tailscale Serve를 구성한다.

```bash
kubectl apply -k ../../02-k8s-manifests/platform/onp/argocd

ansible-playbook -i inventories/onp/proxmox.yaml \
  playbooks/site-argocd-access.yaml
```

접속 주소는 다음과 같다.

```text
https://cntlp-onp-wk-01.tail270b85.ts.net/
```

새 VM의 최초 가입에 사용하는 Tailscale auth key는
`tag:cntlp-wk,tag:cntlp-ui`를 부여할 수 있어야 한다. tailnet 정책에는
`group:cntlp-team`에서 `tag:cntlp-ui`의 TCP `443` 접근만 허용한다.
