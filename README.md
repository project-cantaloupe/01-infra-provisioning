# infra-provisioning

서버와 클러스터를 만드는 코드. **사람이 직접 실행한다.** ArgoCD가 보지 않는다.

## 실행 순서

**전문은 [docs/runbook-build-order.md](docs/runbook-build-order.md) 에 있다.**
각 단계가 왜 그 순서인지, 어기면 어떤 증상이 나오는지까지 적혀 있다.
아래는 요약이다.

```bash
# 0. 상태 버킷과 KMS 키는 terraform 밖에서 손으로 만든다 (docs/runbook-tfstate.md)

# 1. AWS 기반
terraform -chdir=terraform/aws/network apply
terraform -chdir=terraform/aws/egress  apply     # NAT. 없으면 2번이 막힌다

# 2. Vault — 이후 모든 단계가 여기서 시크릿을 읽는다
terraform -chdir=terraform/aws/vault apply
cd ansible && ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-vault.yaml
vault operator init -recovery-shares=5 -recovery-threshold=3    # 사람만. 봉투에 봉인
terraform -chdir=terraform/vault apply                          # 정책·AppRole
#   → 시크릿 4개 투입도 사람이 한다 (docs/runbook-secrets.md)

# 3. 노드 VM. 셋은 서로 독립이다
source scripts/cntlp-env.sh                       # rc=0 이어야 한다
terraform -chdir=terraform/aws/compute apply
terraform -chdir=terraform/gcp         apply
terraform -chdir=terraform/onp         apply      # Proxmox 토큰을 Vault 에서 읽는다

# 4. 클러스터
cd ansible
ansible-inventory --graph                         # 그룹이 비어도 플레이북은 실패하지 않는다
ansible-playbook playbooks/site-cluster.yaml

# 5. 그 위에 얹는 것
terraform -chdir=terraform/aws/database apply
```

**`source scripts/cntlp-env.sh` 없이는 3번 이후가 안 된다.** 그것이 Vault 에서
Proxmox 토큰을 읽어 인벤토리가 요구하는 넷으로 분해하고, SSH 개인키를
ssh-agent 메모리에 넣는다. `rc` 를 확인한다 — 실패하면 온프렘 값을 지우고
1 을 내는데, 무시하고 진행하면 인벤토리가 **에러 없이 호스트 0개**로 성공한다.

Terraform과 Ansible은 서로를 호출하지 않는다. Ansible은 Tailscale 가입,
`kubeadm init/join`, Calico 설치와 최종 검증까지 수행한다. 자세한 준비와
단계별 실행 방법은
[`ansible/README.md`](ansible/README.md)에 있다.

향후 ArgoCD를 설치한 뒤에는 클러스터 변경을 여기서 하지 않고
`k8s-manifests`로 넘긴다.

Argo CD 설치와 최초 Root Application 등록은 클러스터 구성 뒤 별도
부트스트랩 단계에서 수행한다. 이 저장소의 Ansible은 애플리케이션을 배포하지 않는다.

## 런북

| 문서 | 언제 |
|---|---|
| [docs/runbook-build-order.md](docs/runbook-build-order.md) | **아무것도 없는 상태에서 전부 세울 때.** 각 단계의 전제와 순서를 어겼을 때의 증상 |
| [docs/runbook-onboarding.md](docs/runbook-onboarding.md) | 새 팀원이 합류해 자기 파트에 연동할 때. tailnet·Vault 계정·kubeconfig·파트별 작업 |
| [docs/runbook-secrets.md](docs/runbook-secrets.md) | 시크릿을 새로 넣거나 회전할 때. 경로 설계, 정책, terraform·ansible 에서 읽는 법 |
| [docs/runbook-tfstate.md](docs/runbook-tfstate.md) | 상태 버킷·암호화 키를 만들거나 고칠 때. `kms_key_id` 를 빠뜨리면 조용히 되돌아간다 |
| [docs/runbook-onp-vm-recreate.md](docs/runbook-onp-vm-recreate.md) | 온프렘 워커 VM을 지우고 다시 만들어 재조인할 때. 무엇이 멱등이고 무엇이 사람 손을 요구하는지 |
| [docs/vault-architecture.md](docs/vault-architecture.md) | Vault 가 왜 이렇게 생겼는지. 8200 을 안 여는 이유, KMS seal, 주체 분리, 아직 안 끝난 tfstate 문제 |
| [docs/runbook-vault.md](docs/runbook-vault.md) | Vault 를 세우고 백업·복구할 때. `vault operator init` 출력은 화면에 한 번만 나온다 |
| [terraform/onp/README.md](terraform/onp/README.md) | Proxmox 사전 설정(API 토큰, snippets 콘텐츠 타입) |
| [terraform/vault/README.md](terraform/vault/README.md) | Vault 내부 정책·AppRole 을 고칠 때 |

## 구조

```
terraform/
  modules/finops-tags/       공통 관리 태그 모듈 자리
  modules/secops-baseline/   공통 IAM·보안그룹
  aws/network/   VPC, 서브넷, 라우팅, 보안그룹, EICE
  aws/egress/    독립 생성·삭제하는 NAT Gateway
  aws/compute/   Control Plane과 Worker EC2
  aws/database/  애플리케이션용 PostgreSQL RDS
  gcp/           향후 GCP Worker
  onp/           온프렘 Proxmox Worker
ansible/
  inventories/   동적 인벤토리 (손으로 IP 를 적지 않는다)
  roles/         OS 설정, K8s 설치, VPN
  playbooks/     실행 진입점
```

## 인벤토리에 IP 를 적지 않는다

`hosts.ini` 를 만들지 마라. Terraform 이 VM 을 다시 만들면 IP 가 바뀌는데
파일은 그대로 남아 반드시 어긋난다.

대신 Terraform 이 붙인 태그를 Ansible 이 읽어 그룹을 만든다.

| 태그 | 값 |
|---|---|
| `org` | `cntlp` |
| `platform` | `aws` / `gcp` / `onp` |
| `role` | `control-plane` / `service` / `devops` / `monitoring` / `messaging` / `logging` |

AWS·GCP의 공통 관리 태그는 `org`, `owner`, `managed-by`, `lifecycle`,
`platform`이다. Node에는 `role`, 그 밖의 자원에는 필요할 때 `component`를
추가한다. 실제 회계 비용센터가 없으므로 `cost-center`는 사용하지 않는다.

## Terraform 상태는 S3 에 둔다

AWS의 Network, Egress, Compute, Database와 GCP, On-Prem 상태는 S3 backend의
서로 다른 키에 저장한다.

## 클러스터 안쪽 거버넌스는 여기 없다

파드 보안이나 리소스 쿼터는 [`k8s-manifests/governance/`](../k8s-manifests/) 에 있다.
여기는 클라우드 자원(태그, IAM, 보안그룹) 쪽만 담당한다.
