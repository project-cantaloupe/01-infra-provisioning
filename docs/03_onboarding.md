# 03 — 합류와 파트 연동

**새 사람이 이 인프라에 붙어서 자기 파트를 작업할 수 있게 되기까지.**

1~4 는 합류시키는 사람과 합류하는 사람이 같이 한다.
5~7 은 파트별로 갈린다.

**시작하기 전에 [01 아키텍처](01_architecture.md) 를 읽는다.** 노드가 어디에
몇 대 있고 무엇이 인터넷에 열려 있는지를 알고 있어야 아래가 이해된다.

---

## 1. tailnet 에 들어간다

이 인프라는 **Tailscale 메시 안에 들어와야 아무것도 보인다.** SSH 도 K8s API 도
Vault 도 마찬가지다. 그래서 이게 첫 단계다.

**관리자가 할 것** — Tailscale admin 콘솔에서 초대를 보내고, 그 계정을
팀원 그룹(`group:*-team`)에 넣는다.

**본인이 할 것**

```bash
tailscale up
tailscale status                      # 노드 목록이 보이면 성공
tailscale ping cntlp-aws-cp-01        # 이름으로 바로 닿아야 한다
```

> **`tailscale status` 에 노드가 보이는데 닿지 않으면 ACL 문제다.**
> 목록에 나오는 것과 접근 권한은 별개다. 관리자에게 자기 계정이 팀원
> 그룹에 들어갔는지 확인을 요청한다.

팀원 그룹이 갖는 권한은 노드 SSH(22), K8s API(6443), UI 포트,
Pod/Service CIDR 이다. **관리자 그룹과 달리 개인 기기에는 못 닿는다.**

## 2. 워크스테이션을 준비한다

```bash
git clone <repo> && cd 01-infra-provisioning
./scripts/bootstrap-workstation.sh
cd ansible && ansible-galaxy collection install -r requirements.yml && cd ..
```

`terraform`(≥1.10), `ansible`, `aws`, `vault`, `kubectl` 이 들어간다.

## 3. Vault 계정을 받는다

**관리자가 할 것.** 먼저 아래 [5절](#5-정책을-새로-만들어야-한다--아직-안-풀린-숙제) 을 읽는다.
기존 `pneuma` 정책을 그대로 주면 안 된다.

```bash
export VAULT_TOKEN='<봉투의 root 토큰>'
vault write auth/userpass/users/<이름> password=- policies=<정책이름>
```

**본인이 할 것**

```bash
export VAULT_ADDR=https://cntlp-aws-vault-01.<tailnet>.ts.net:8200
vault login -method=userpass username=<이름>
vault token lookup | grep -E 'policies|ttl'      # 정책과 TTL 8h 확인
```

`VAULT_TOKEN` 을 export 할 필요는 없다. `vault login` 이 `~/.vault-token` 에
저장하고, terraform·ansible·스크립트가 전부 그 파일을 읽는다.

**토큰 수명은 8시간이다.** 아침에 한 번 로그인하면 하루가 간다.

## 4. 환경을 세우고 확인한다

이 리포의 모든 작업은 이 한 줄에서 시작한다.

```bash
source scripts/cntlp-env.sh
echo "rc=$?"                # 0 이어야 한다
```

### `cntlp-env.sh` 가 하는 일

| 순서 | 무엇을 |
|---|---|
| 1 | AWS 자격증명을 ansible 이 보는 환경변수로 옮긴다 |
| 2 | `ANSIBLE_CONFIG` 를 고정한다 |
| 3 | **Vault 토큰이 실제로 쓸 수 있는지 확인한다** (`vault token lookup`) |
| 4 | `secret/onp/proxmox` 를 읽어 `PROXMOX_*` 넷으로 분해한다 |
| 5 | `secret/ssh/cntlp-private` 를 **ssh-agent 메모리에만** 넣는다 (`-t 8h`) |

1·2 가 3 보다 앞인 것이 의도다. **Vault 를 세우는 작업(`site-vault.yaml`)은
Vault 없이 돌아야 하기 때문이다.** 그래서 AWS 작업은 Vault 가 없어도 된다.

3 이 존재 여부가 아니라 **실제 호출**인 것도 의도다. 토큰 파일은 있는데
만료·폐기된 경우를 존재 검사로는 못 거른다.

개인키를 파일로 내리지 않고 agent 에만 넣는 이유는, 파일로 쓰면 Vault 에
원본이 있는 상태에서 평문 사본이 하나 느는 것이라서다. `ssh-add -t 8h` 의
수명은 **Vault 토큰 TTL 과 같은 값**이다. 다르면 한쪽이 살아 있는데 다른
쪽이 죽어서 원인을 헷갈린다.

### `rc` 를 반드시 본다

0 이 아니면 스크립트가 `PROXMOX_*` 를 **지운다.** 그 상태로 ansible 을 돌리면
**에러 없이 호스트 0개**로 성공한다. 실패를 실패로 보이게 하려고 지우는 것이다.

```bash
ssh-add -l | grep cantaloupe-infra           # agent 에 키가 있나
cd ansible && ansible-inventory --graph      # 그룹이 다 보이나
ansible platform_aws:platform_gcp:platform_onp -m ping
```

`ansible-inventory --graph` 를 먼저 보는 습관을 들인다. 그룹이 비어 있어도
플레이북은 실패하지 않는다.

---

## 5. 정책을 새로 만들어야 한다 — 아직 안 풀린 숙제

> ⚠️ **지금 사람용 정책은 `pneuma` 하나뿐이고, 그것은 SSH 개인키를 포함해
> 모든 시크릿을 읽고 쓴다.** 그대로 팀원에게 주면 **모든 노드에 root 로
> 들어갈 권한을 주는 것과 같다.**

`terraform/vault/policies/human.hcl` 이 그 정책이다. 팀원을 붙이려면 좁은
정책을 새로 만든다. 판단 기준은 [04 §1](04_secrets.md#1-경로를-먼저-정한다)
과 같다 — **무엇을 읽어야 하는가**에서 시작한다.

대부분의 파트는 시크릿을 직접 읽을 필요가 없다. K8s 워크로드로 올라가는
것이면 시크릿은 ESO 가 주입하고, 사람은 `kubectl` 만 있으면 된다.

```hcl
# 예시 — 클러스터만 쓰는 팀원. 시크릿을 못 읽는다.
path "auth/token/lookup-self" { capabilities = ["read"] }
path "sys/health"             { capabilities = ["read"] }
```

자기 파트 전용 시크릿이 필요하면 경로를 따로 판다.

```hcl
path "secret/data/<파트>/*"     { capabilities = ["read"] }
path "secret/metadata/<파트>/*" { capabilities = ["read"] }
```

정책 파일을 만들고 `policies.tf` 에 `vault_policy` 를 추가한 뒤 apply 한다.
**이 apply 에는 root 토큰이 필요하다** — `pneuma` 로는 정책을 못 바꾼다.

---

## 6. 클러스터에 붙는다

```bash
scp ubuntu@cntlp-aws-cp-01:/etc/kubernetes/admin.conf ~/.kube/config
kubectl get nodes -L platform,role
```

> ⚠️ `admin.conf` 는 **클러스터 전체 관리자 권한**이다. 파트별로 나눠 주려면
> RBAC 을 따로 짜야 하고, 그건 아직 없다. 5절과 같은 성격의 숙제다.
> 지금은 소수 인원이라 이렇게 쓰고 있다는 사실을 알고 쓴다.

자기 파트 노드에만 올리려면 라벨로 고정한다. 어느 노드가 무슨 역할인지는
[01 §1](01_architecture.md#1-전체-모양) 의 표에 있다.

```yaml
nodeSelector:
  role: monitoring        # 또는 logging / devops / service
```

라벨 규약은 팀 협약이다 → `decisions/20260729_k8s-labeling-convention.md`.
**`Service` 의 selector 에는 `app` 라벨만 쓴다.**

---

## 7. 파트별 연동

### 클러스터에 올라가는 것 (모니터링·로깅·서비스·CI)

**이 리포에 매니페스트를 넣지 않는다.** 클러스터 안쪽은 ArgoCD 가 가져간다
→ `repos/02-k8s-manifests`.

```
이 리포            서버·클러스터를 만든다. 사람이 직접 실행한다
02-k8s-manifests   클러스터 위에 올라가는 것. ArgoCD 가 본다
```

`kubectl apply` 를 손으로 하면 ArgoCD 가 다음 동기화에서 되돌린다.

시크릿이 필요하면 매니페스트에 넣지 말고 ESO 를 쓴다. 아직 없으므로 그
파트를 시작하기 전에 관리자와 순서를 맞춘다.

### 새 노드가 필요한 경우

노드를 늘리는 것은 terraform 이다. 영역에 따라 스택이 갈린다.

| 어디에 | 스택 | 비고 |
|---|---|---|
| AWS | `terraform/aws/compute` | |
| GCP | `terraform/gcp` | |
| 온프렘 | `terraform/onp` | Proxmox. Vault 를 읽는다 |

만든 뒤에는 ansible 로 클러스터에 넣는다.

```bash
cd ansible
ansible-playbook playbooks/site-prerequisites.yaml --limit <새노드>
ansible-playbook playbooks/site-workers.yaml       --limit <새노드>
ansible-playbook playbooks/site-node-labels.yaml
```

**`role` 태그를 terraform 에서 올바로 붙인다.** 허용값은
`control-plane`·`service`·`devops`·`messaging`·`monitoring`·`logging` 이고,
`site-node-labels.yaml` 이 검증한다. 다른 값이면 그 플레이북이 실패한다.

온프렘 VM 을 **다시 만드는** 것은 절차가 따로 있다 →
[07](07_onp-vm-recreate.md).

### 인프라 코드를 고치는 경우

```bash
git checkout -b <유형>/<슬러그>      # feat / fix / chore / docs
```

**`main` 에 직접 커밋하지 않는다.** 인프라는 되돌리는 비용이 크다 —
`terraform apply` 가 실제 자원을 만들고, 잘못된 커밋이 `main` 에 있으면
남은 자원과 코드가 어긋난다.

apply 전에 반드시 `plan` 을 사람이 읽는다. 특히 **`destroy` 가 섞여 있는지**
본다. `terraform/aws/network` 는 tfvars 없이 apply 하면 살아 있는 EICE 를
지우려 든다.

---

## 자주 막히는 것

일상 작업 중에 만나는 것들이다. Vault 자체의 고장은
[05 §8](05_vault-ops.md#8-막힐-때), 온프렘 VM 은
[07 트러블슈팅](07_onp-vm-recreate.md#트러블슈팅) 을 본다.

| 증상 | 원인 |
|---|---|
| `Invalid URL '/api2/json/nodes'` | `cntlp-env.sh` 를 안 돌렸거나 `rc≠0`. `PROXMOX_*` 가 비었다 |
| `Permission denied (publickey)` | ssh-agent 에 키가 없다. `source scripts/cntlp-env.sh` 를 다시 |
| `0 hosts matched` 로 성공 | 인벤토리 그룹이 비었다. `ansible-inventory --graph` 로 확인 |
| `permission denied` (Vault) | 정책에 그 경로가 없다. `secret/data/` 와 `secret/metadata/` **둘 다** 필요 |
| `failed to create limited child token` | provider 에 `skip_child_token = true` 가 빠졌다 |
| terraform 은 되는데 ansible 만 안 됨 | 자격증명 경로가 다르다. `aws login` 후 `source scripts/cntlp-env.sh` |
| `tailscale up` 성공인데 안 닿음 | ACL 에 그 태그 규칙이 없다. 노드는 떴는데 고립된 것 |

공통점이 있다. **대부분 에러가 아니라 이상한 성공으로 나타난다.**

---

## 합류시키는 쪽 체크리스트

- [ ] Tailscale 초대 + 팀원 그룹(`group:*-team`)에 추가
- [ ] tailnet ACL 에 그 그룹의 접근 규칙이 있는지 확인
- [ ] **Vault 정책을 새로 만든다** (`pneuma` 를 그대로 주지 않는다 → 5절)
- [ ] `vault write auth/userpass/users/<이름> password=- policies=<정책>`
      — 비밀번호는 `-` 로 stdin 에서 받는다
- [ ] kubeconfig 전달 (RBAC 이 생기기 전까지의 임시 방편임을 알린다)
- [ ] 담당 파트의 `role` 라벨과 노드를 알려준다
- [ ] [01](01_architecture.md) 과 이 문서를 읽게 한다
