# 런북 — 팀원 합류와 파트 연동

**새 사람이 이 인프라에 붙어서 자기 파트를 작업할 수 있게 되기까지.**

앞의 절반(1~4)은 합류시키는 사람과 합류하는 사람이 같이 한다.
뒤의 절반(5~)은 파트별로 갈린다.

전체 구축 순서는 [`runbook-build-order.md`](runbook-build-order.md),
시크릿을 다루는 법은 [`runbook-secrets.md`](runbook-secrets.md).

---

## 이 인프라의 모양

먼저 이것부터 알아야 나머지가 이해된다.

```
                    Tailscale 메시 (tailnet)
   ┌──────────────────────┴──────────────────────┐
   │                                             │
 AWS                        GCP              온프렘 (Proxmox)
 ├ cntlp-aws-cp-01   ← 컨트롤플레인   ├ cntlp-gcp-wk-01   ├ cntlp-onp-wk-01
 ├ cntlp-aws-wk-01                    └ cntlp-gcp-wk-02
 └ cntlp-aws-vault-01 ← 시크릿 저장소

 단일 K8s 클러스터. 물리 위치는 노드 라벨 platform 으로만 구분한다.
```

**인터넷에 노출되는 것은 오디오 앱뿐이다.** 나머지는 전부 메시 안쪽이다.
SSH, K8s API, 각종 UI — 전부 tailnet 에 들어와야 보인다.

| 라벨 | 노드 | 무엇을 올리나 |
|---|---|---|
| `role=control-plane` | `cntlp-aws-cp-01` | K8s 컨트롤플레인 |
| `role=service` | `cntlp-aws-wk-01` | 서비스 워크로드 |
| `role=monitoring` | `cntlp-gcp-wk-01` | 모니터링 스택 |
| `role=logging` | `cntlp-gcp-wk-02` | 로깅 스택 |
| `role=devops` | `cntlp-onp-wk-01` | CI, 레지스트리 |

---

## 1. tailnet 에 들어간다

**관리자가 할 것** — Tailscale admin 콘솔에서 초대를 보내고, 그 계정을
팀원 그룹(`group:*-team`)에 넣는다.

**본인이 할 것**

```bash
tailscale up
tailscale status          # 노드 목록이 보이면 성공
```

노드 이름으로 바로 닿아야 한다.

```bash
tailscale ping cntlp-aws-cp-01
```

> **`tailscale status` 에 노드가 보이는데 닿지 않으면 ACL 문제다.**
> 목록에 나오는 것과 접근 권한은 별개다. 관리자에게 자기 계정이 팀원 그룹에
> 들어갔는지 확인을 요청한다.

팀원 그룹이 갖는 권한은 대략 이렇다 — 노드 SSH(22), K8s API(6443),
UI 포트, Pod/Service CIDR. **관리자 그룹과 달리 개인 기기에는 못 닿는다.**

## 2. 워크스테이션을 준비한다

```bash
git clone <repo> && cd 01-infra-provisioning
./scripts/bootstrap-workstation.sh
cd ansible && ansible-galaxy collection install -r requirements.yml && cd ..
```

`terraform`(≥1.10), `ansible`, `aws`, `vault`, `kubectl` 이 들어간다.

## 3. Vault 계정을 받는다

**관리자가 할 것.** 정책은 아래 「5. 정책을 새로 만들어야 한다」를 먼저 읽는다.

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
저장하고 terraform·ansible·스크립트가 전부 그 파일을 읽는다.

**토큰 수명은 8시간이다.** 아침에 한 번 로그인하면 하루가 간다.

## 4. 환경을 세우고 확인한다

```bash
source scripts/cntlp-env.sh
echo "rc=$?"                # 0 이어야 한다
```

이게 하는 일 — Vault 에서 Proxmox 토큰을 읽어 넷으로 분해, SSH 개인키를
ssh-agent 메모리에 적재(8h, 디스크에 안 쓴다), AWS 자격증명 이관,
`ANSIBLE_CONFIG` 고정.

**`rc` 를 반드시 본다.** 0 이 아니면 온프렘 값이 지워진 상태이고, 그대로
ansible 을 돌리면 **에러 없이 호스트 0개**로 성공한다.

```bash
# 확인
ssh-add -l | grep cantaloupe-infra
cd ansible && ansible-inventory --graph
ansible platform_aws:platform_gcp:platform_onp -m ping
```

`ansible-inventory --graph` 를 먼저 보는 습관을 들인다. 그룹이 비어 있어도
플레이북은 실패하지 않는다.

---

## 5. 정책을 새로 만들어야 한다 — 아직 안 풀린 부분

> ⚠️ **지금 사람용 정책은 `pneuma` 하나뿐이고, 그것은 SSH 개인키를 포함해
> 모든 시크릿을 읽고 쓴다.** 그대로 팀원에게 주면 **모든 노드에 root 로
> 들어갈 권한을 주는 것과 같다.**

`terraform/vault/policies/human.hcl` 이 그 정책이다. 팀원을 붙이려면 좁은
정책을 새로 만든다. 판단 기준은 [`runbook-secrets.md`](runbook-secrets.md) 의
「경로를 먼저 정한다」와 같다 — **무엇을 읽어야 하는가**에서 시작한다.

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
# 컨트롤플레인에서 kubeconfig 를 받는다 (관리자에게 요청하거나 직접)
scp ubuntu@cntlp-aws-cp-01:/etc/kubernetes/admin.conf ~/.kube/config
kubectl get nodes -L platform,role
```

> ⚠️ `admin.conf` 는 **클러스터 전체 관리자 권한**이다. 파트별로 나눠 주려면
> RBAC 을 따로 짜야 하고, 그건 아직 없다. 5번과 같은 성격의 숙제다.
> 지금은 소수 인원이라 이렇게 쓰고 있다는 사실을 알고 쓴다.

자기 파트 노드에만 올리려면 라벨로 고정한다.

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
이 리포          서버·클러스터를 만든다. 사람이 직접 실행한다
02-k8s-manifests 클러스터 위에 올라가는 것. ArgoCD 가 본다
```

`kubectl apply` 를 손으로 하면 ArgoCD 가 다음 동기화에서 되돌린다.

시크릿이 필요하면 매니페스트에 넣지 말고 ESO 를 쓴다. 아직 없으므로
그 파트를 시작하기 전에 관리자와 순서를 맞춘다.

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
`control-plane`·`service`·`devops`·`monitoring`·`logging` 이고,
`site-node-labels.yaml` 이 검증한다. 다른 값이면 그 플레이북이 실패한다.

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

| 증상 | 원인 |
|---|---|
| `Invalid URL '/api2/json/nodes'` | `cntlp-env.sh` 를 안 돌렸거나 `rc≠0`. `PROXMOX_*` 가 비었다 |
| `Permission denied (publickey)` | ssh-agent 에 키가 없다. `source scripts/cntlp-env.sh` 를 다시 |
| `0 hosts matched` 로 성공 | 인벤토리 그룹이 비었다. `ansible-inventory --graph` 로 확인 |
| `permission denied` (Vault) | 정책에 그 경로가 없다. `secret/data/` 와 `secret/metadata/` 둘 다 필요 |
| `failed to create limited child token` | provider 에 `skip_child_token = true` 가 빠졌다 |
| terraform 은 되는데 ansible 만 안 됨 | 자격증명 경로가 다르다. `aws login` 후 `source scripts/cntlp-env.sh` |
| `tailscale up` 성공인데 안 닿음 | ACL 에 그 태그 규칙이 없다. 노드는 떴는데 고립된 것 |
| Vault 가 `sealed` | KMS 접근 실패. IAM·네트워크를 본다. **봉투는 안 연다** |

공통점이 있다. **대부분 에러가 아니라 이상한 성공으로 나타난다.**
"성공했는데 아무 일도 안 일어났다" 싶으면 이 표를 먼저 본다
→ `articles/20260731_vault-secret-centralization.md`

---

## 합류시키는 쪽 체크리스트

- [ ] Tailscale 초대 + 팀원 그룹(`group:*-team`)에 추가
- [ ] tailnet ACL 에 그 그룹의 접근 규칙이 있는지 확인
- [ ] **Vault 정책을 새로 만든다** (`pneuma` 를 그대로 주지 않는다)
- [ ] `vault write auth/userpass/users/<이름> password=- policies=<정책>`
      — 비밀번호는 `-` 로 stdin 에서 받는다
- [ ] kubeconfig 전달 (RBAC 이 생기기 전까지의 임시 방편임을 알린다)
- [ ] 담당 파트의 `role` 라벨과 노드를 알려준다
- [ ] `runbook-build-order.md` 와 이 문서를 읽게 한다
