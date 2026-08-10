# infra-provisioning

서버와 클러스터를 만드는 코드. **사람이 직접 실행한다.** ArgoCD가 보지 않는다.

## 실행 순서

**전문은 워크스페이스의 `references/20260801_infra-02-build-order.md` 에 있다.**
각 단계가 왜 그 순서인지, 어기면 어떤 증상이 나오는지까지 적혀 있다.
아래는 요약이다.

```bash
# 0. 상태 버킷과 KMS 키는 terraform 밖에서 손으로 만든다 (references/20260801_infra-06-tfstate.md)

# 1. AWS 기반
terraform -chdir=terraform/aws/network apply
terraform -chdir=terraform/aws/egress  apply     # NAT. 없으면 2번이 막힌다

# 2. Vault — 이후 모든 단계가 여기서 시크릿을 읽는다
terraform -chdir=terraform/aws/vault apply
cd ansible && ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-vault.yaml
vault operator init -recovery-shares=5 -recovery-threshold=3    # 사람만. 봉투에 봉인
terraform -chdir=terraform/vault apply                          # 정책·AppRole
#   → 시크릿 4개 투입도 사람이 한다 (references/20260801_infra-04-secrets.md)

# 3. 노드 VM. 셋은 서로 독립이다
source scripts/cntlp-env.sh                       # rc=0 이어야 한다
terraform -chdir=terraform/aws/compute apply
terraform -chdir=terraform/gcp         apply
terraform -chdir=terraform/onp         apply      # Proxmox 토큰을 Vault 에서 읽는다

# 4. 클러스터
cd ansible
ansible-inventory -i inventories/aws/aws_ec2.yaml --graph   # 그룹이 비어도 플레이북은 실패하지 않는다
ansible-playbook  -i inventories/aws/aws_ec2.yaml playbooks/site-cluster.yaml

# 5. 그 위에 얹는 것
terraform -chdir=terraform/aws/database apply

# 6. Istio ingress gateway 가 준비된 뒤에 Public NLB 를 만든다.
#    게이트웨이가 없으면 타깃이 비어 헬스체크가 계속 실패한다
terraform -chdir=terraform/aws/edge init -reconfigure
terraform -chdir=terraform/aws/edge apply
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

## 문서는 워크스페이스에 있다

**절차 문서는 이 리포에 두지 않는다.** 워크스페이스의 `references/` 가 갖는다.
색인은 `references/20260801_infra-00-index.md` 이고, 슬러그의 번호가 읽는
순서다.

| # | 슬러그 | 언제 편다 |
|---|---|---|
| 01 | `infra-01-architecture` | 왜 이 모양인지. **처음 온 사람이 먼저 읽는다** |
| 02 | `infra-02-build-order` | 아무것도 없는 상태에서 전부 세울 때 |
| 03 | `infra-03-onboarding` | 새 팀원이 붙어서 자기 파트를 시작할 때 |
| 04 | `infra-04-secrets` | 비밀 값을 새로 넣거나 바꿀 때 |
| 05 | `infra-05-vault-ops` | 백업·복구·인스턴스 재생성 |
| 06 | `infra-06-tfstate` | 상태 버킷·암호화 키를 만들거나 고칠 때 |
| 07 | `infra-07-onp-vm-recreate` | Proxmox 워커를 지우고 다시 만들 때 |

위 일곱은 전부 `references/20260801_<슬러그>.md` 다. 코드 주석의
`→ references/…` 도 같은 곳을 가리킨다.

한 건이 더 있고 슬러그 규칙이 다르다 — 번호 순서에 들어가는 구축 절차가
아니라 필요할 때만 펴는 전환 런북이라서다.

| 슬러그 | 언제 편다 |
|---|---|
| `references/20260810_k8s-kubelet-serving-tls.md` | Metrics Server 가 kubelet 10250 을 검증하도록 serving 인증서를 노드 한 대씩 전환할 때 |

**리포에 남는 문서는 디렉터리 README 뿐이다.** 그 코드를 고칠 때 같이 보는
것이라 코드 옆에 둔다 — `ansible/README.md`,
`ansible/roles/vault-server/README.md`, `packer/aws/kubernetes-worker/README.md`,
그리고 `terraform/` 의 `onp`·`vault`·`audio`·`database`·`edge`·`karpenter`.
**새로 늘리지 않는다.** 절차가 들어가기 시작하면 `references/` 로 옮긴다.

## 구조

```
terraform/
  modules/finops-tags/       공통 관리 태그 모듈 자리
  modules/secops-baseline/   공통 IAM·보안그룹
  aws/network/   VPC, 서브넷, 라우팅, 보안그룹, EICE
  aws/egress/    독립 생성·삭제하는 NAT Gateway
  aws/vault/     Vault EC2 · auto-unseal KMS 키 · 스냅샷 버킷
  aws/compute/   Control Plane과 Worker EC2
  aws/database/  애플리케이션용 PostgreSQL RDS
  aws/edge/      Public NLB, Target Group, DNS, cert-manager IAM
  aws/karpenter/ Golden Image Builder 와 향후 Karpenter AWS 기반 자원
  gcp/           GCP Worker
  onp/           온프렘 Proxmox Worker
  vault/         Vault 내부 — 정책·AppRole·감사 (자원이 아니라 설정)
ansible/
  inventories/   동적 인벤토리 (손으로 IP 를 적지 않는다)
  roles/         OS 설정, K8s 설치, VPN, Vault 설치
  playbooks/     실행 진입점
packer/
  aws/kubernetes-worker/     Karpenter Worker Golden Image
scripts/
  bootstrap-workstation.sh   도구 설치
  cntlp-env.sh               Vault 에서 값을 당겨 셸을 세운다
  join-worker.sh             워커 조인 사전 점검과 실행
```

`aws/vault/` 와 `vault/` 는 다른 것이다. 앞은 **서버를 만들고**, 뒤는 **그
안의 정책을 만든다.** 그래서 앞은 AWS 자격증명으로, 뒤는 Vault 토큰으로 돈다.

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

열세 스택 전부가 `cntlp-aws-tfstate` 버킷의 서로 다른 `key` 를 쓴다.
버킷과 KMS 키만 terraform 밖에서 손으로 만든다 — 자기 상태를 자기가 만든
자원에 담을 수 없기 때문이다.

**새 스택을 만들 때 `backend.tf` 에 `kms_key_id` 를 빠뜨리지 않는다.**
`encrypt = true` 만으로는 SSE-S3 이고, apply 는 성공하므로 아무도 모른다
→ `references/20260801_infra-06-tfstate.md`

```bash
# 빠진 스택을 찾는다
for f in $(grep -rl --include=backend.tf 'backend "s3"' terraform); do
  grep -q kms_key_id "$f" || echo "$f"
done
```

## 클러스터 안쪽 거버넌스는 여기 없다

파드 보안이나 리소스 쿼터는 [`k8s-manifests/governance/`](../02-k8s-manifests/) 에 있다.
여기는 클라우드 자원(태그, IAM, 보안그룹) 쪽만 담당한다.
