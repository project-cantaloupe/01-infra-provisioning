# Ansible Kubernetes 구성

Terraform으로 VM과 네트워크를 만든 뒤 **사람이 별도로 실행**하는 Kubernetes
구성 자동화다. Terraform의 `apply`가 Ansible을 호출하지 않는다.

AWS 동적 인벤토리는 실행 중인 EC2 중 다음 태그가 있는 노드만 찾고, EICE
터널로 SSH 접속한다.

| 태그 | 값 |
|---|---|
| `org` | `cntlp` |
| `platform` | `aws` |
| `role` | `control-plane` 또는 `service` |

## 자동화 범위

| 역할 | 수행 내용 |
|---|---|
| `common` | swap 영구 비활성화, 커널 모듈과 sysctl 설정 |
| `vpn-mesh` | Tailscale 설치·가입, 노드의 Tailscale IPv4 수집 |
| `containerd` | containerd 설치, `SystemdCgroup=true` 설정 |
| `kubeadm-common` | kubelet·kubeadm·kubectl 버전 고정 및 hold |
| `kubeadm-control-plane` | 단일 Control Plane 초기화와 필수 노드 라벨 적용 |
| `cni-calico` | Tigera Operator와 Calico VXLAN 네트워크 설치 |
| `kubeadm-worker` | 단기 토큰 생성, Worker 가입, 토큰 폐기와 라벨 적용 |
| `site-node-labels` | 수동 join 노드까지 이름을 기준으로 필수 라벨 보정 |

클러스터 이름은 `cntlp-k8s`이고 Kubernetes API와 각 노드의
`InternalIP`에는 Tailscale IPv4를 사용한다. 플랫폼 구분은 노드 이름과
`platform` 라벨에만 남기며 AWS Worker에는 `role=service`를 적용한다.

## 재실행 안전성

- `/etc/kubernetes/admin.conf`가 있으면 `kubeadm init`을 다시 실행하지 않는다.
- `/etc/kubernetes/kubelet.conf`가 있으면 Worker를 다시 join하지 않는다.
- 이미 tailnet에 가입한 노드는 `tailscale up`을 다시 실행하지 않는다.
- 기존 수동 구축 Worker에 `--node-ip` 영구 설정이 없으면 한 번 보완하고
  kubelet을 재시작한다.
- 정상 재구성 과정에서는 `kubeadm reset`을 실행하지 않는다.

따라서 현재 클러스터에 다시 실행할 수 있지만, 클러스터 버전·Pod CIDR·CNI
같은 불변에 가까운 값의 변경은 일반 재실행이 아니라 별도 업그레이드 절차로
다뤄야 한다.

## 로컬 준비

`ansible-core 2.19`의 컨트롤 노드는 Python 3.11~3.13이 필요하다.

```bash
cd <리포 루트>/ansible

python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p .collections
```

## 실행 전 환경변수

**손으로 export 하지 않는다.** `scripts/cntlp-env.sh` 가 전부 세운다 —
Vault 에서 값을 읽어야 하므로 먼저 로그인한다.

```bash
cd <리포 루트>
source ansible/.venv/bin/activate

export VAULT_ADDR=https://cntlp-aws-vault-01.<tailnet>.ts.net:8200
vault login -method=userpass username=<이름>      # 토큰 TTL 8h

source scripts/cntlp-env.sh
echo "rc=$?"        # 0 이어야 한다
```

이게 세우는 것 — Proxmox 접속 4종(Vault 의 `secret/onp/proxmox`),
SSH 개인키(`secret/ssh/cntlp-private` → ssh-agent 메모리, 8h),
AWS 자격증명, `ANSIBLE_CONFIG`.

> **`rc` 를 확인한다.** Vault 단계가 실패하면 `PROXMOX_*` 를 지우고 1 을 낸다.
> 무시하고 진행하면 온프렘 인벤토리가 **에러 없이 호스트 0개**로 성공한다.
> AWS 자격증명과 `ANSIBLE_CONFIG` 은 그 경우에도 세워져 있다 — AWS 작업은
> Vault 없이도 되어야 하기 때문이다.

**Tailscale auth key 를 손으로 넘기지 않는다.** 온프렘은 group_vars 가 Vault 의
`secret/onp/tailscale` 에서 읽고, 이미 가입된 노드는 그 조회조차 하지 않는다
(jinja 지연 평가). 새 영역을 처음 세울 때만 예외적으로 환경변수를 쓴다 —
그 시점에는 Vault 가 아직 없다 → `references/20260801_infra-02-build-order.md` 3-2절

**개인키 경로도 지정하지 않는다.** `ansible_ssh_private_key_file` 은
group_vars 에서 지웠다. ssh-agent 를 쓴다 — Vault 에서 당겨 파일로 쓰면
원본이 있는 상태에서 평문 사본이 하나 는다.

## 전체 자동 실행

먼저 인벤토리와 SSH를 확인한 뒤 통합 플레이북을 실행한다.

```bash
ansible-inventory --graph
ansible platform_aws:platform_gcp:platform_onp -m ansible.builtin.ping

ansible-playbook playbooks/site-cluster.yaml --syntax-check
ansible-playbook playbooks/site-cluster.yaml
```

`ansible-inventory --graph` 를 먼저 보는 것이 습관이어야 한다.
**그룹이 비어 있어도 플레이북은 실패하지 않는다** — `0 hosts matched` 는
성공으로 끝난다. 이 리포가 반복해 밟은 함정이다.

`site-cluster.yaml`의 실행 순서는 다음과 같다.

1. 전체 노드 OS·Tailscale·containerd·Kubernetes 패키지 준비
2. 단일 Control Plane 구성
3. Calico CNI 구성
4. 모든 Worker 가입
5. 클러스터 전체 노드의 `platform`/`role` 라벨 보정
6. 노드 Ready, Tailscale InternalIP, 필수 라벨 검증

## 단계별 실행

문제가 생긴 단계를 구분하거나 구축 과정을 확인하려면 같은 순서로 하나씩
실행한다.

```bash
ansible-playbook playbooks/site-prerequisites.yaml
ansible-playbook playbooks/site-control-plane.yaml
ansible-playbook playbooks/site-cni.yaml
ansible-playbook playbooks/site-workers.yaml
ansible-playbook playbooks/site-node-labels.yaml
ansible-playbook playbooks/site-verify.yaml
```

마지막 검증 플레이북은 클러스터 설정을 변경하지 않는다. 언제든 다음 명령으로
현재 상태만 다시 확인할 수 있다.

```bash
ansible-playbook playbooks/site-verify.yaml
```

## GCP와 On-Prem Worker

GCP와 On-Prem도 동적 인벤토리를 사용한다. GCP VM에는 Terraform이
`platform=gcp`와 `role=monitoring|logging`을, Proxmox VM에는
`platform-onp`와 `role-devops`를 부여한다. 접속 정보나 고정 IP를 정적
`hosts.ini`에 복사하지 않는다.
