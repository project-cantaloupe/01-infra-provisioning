# 런북 — Vault

시크릿 중앙 저장소를 세우고, 백업하고, 되살리는 절차.

**되돌릴 수 없는 단계가 하나 있다** — `vault operator init`. 출력이 화면에 한 번만
나오고 다시 볼 수 없다. 그 앞뒤를 [2절](#2-초기화--한-번만-되돌릴-수-없다)에 적었다.
순서만 필요하면 [전체 순서](#전체-순서)로 간다.

대상: `cntlp-aws-vault-01` / Private Subnet / 퍼블릭 IP 없음 / raft 단일 노드.

관련: `tasks/doing/006_vault-setup.md` (설계), `terraform/vault/README.md` (정책),
`ansible/roles/vault-server/README.md` (설치).

---

## 1. 이 노드가 다른 노드와 다른 점 4개

### 1-1. `egress` 스택 없이는 부트스트랩되지 않는다

Private Subnet 이라 인터넷으로 나가는 길이 NAT Gateway 뿐이다. NAT 가 없으면
apt 도 tailnet 조인도 못 한다.

**그리고 접근 경로가 메시뿐이라, NAT 를 지우면 인스턴스는 살아 있는데 아무도
닿을 수 없게 된다.** `egress` 는 비용을 아끼려고 destroy 하도록 만든 스택이므로
이 일이 실제로 일어난다 → [6절](#6-egress-를-지울-때-vault-를-먼저-내린다)

`terraform/aws/vault/data.tf` 의 `check` 블록이 apply 때 NAT 경로를 검사한다.

### 1-2. 메시에 들어가기 전 접근 수단이 EICE 뿐이다

Security Group 에 인바운드가 EICE SSH 하나뿐이고 퍼블릭 IP 가 없다.
동적 인벤토리의 `ansible_ssh_common_args` 가 `aws ec2-instance-connect
open-tunnel` 로 그 터널을 연다.

**EICE 는 `lifecycle = "temporary"` 자원이다.** 메시가 안정되면 지울 것이고,
그러면 Vault 를 다시 세울 때 한시적으로 다시 켜야 한다.

```bash
terraform -chdir=terraform/aws/network apply \
  -var enable_eice=true -var eice_expires_on=2026-12-31
```

### 1-3. K8s 노드가 아니다

`role` 태그를 붙이지 않는다 — `role` 은 Kubernetes 노드 전용 라벨이고 허용값이
정해져 있다 (`decisions/20260729_k8s-labeling-convention`). 대신 `component=vault`
태그로 `component_vault` 그룹에 들어간다.

`site-prerequisites.yaml` 이 `!component_vault` 로 제외한다. 안 빼면 K8s 노드가
아닌 곳에 containerd 와 kubeadm-common 이 깔리는데 **에러 없이 성공한다.**

### 1-4. 감사 로그가 차면 Vault 가 멈춘다

감사 장치가 켜져 있으면 로그를 쓸 수 없을 때 Vault 가 모든 요청을 거부한다.
의도된 동작이다 — 감사 없이 시크릿을 내주지 않는다.

`vault-server` 롤이 logrotate 를 넣지만 디스크는 사람이 본다 →
[8절](#8-막힐-때)

---

## 2. 초기화 — 한 번만, 되돌릴 수 없다

**출력이 화면에 한 번만 나온다.** 터미널을 닫으면 끝이다.

```bash
vault operator init -recovery-shares=5 -recovery-threshold=3
```

`-key-shares` 가 **아니다.** awskms seal 에서는 unseal 키가 KMS 에 있고 사람이
받는 것은 **recovery** 키다 — rekey 와 root 토큰 재발급에만 쓴다.
헷갈려 `-key-shares` 로 돌리면 그건 한 번만 할 수 있는 일을 틀리게 한 것이다.

### 봉인 대상은 둘뿐이다

| 값 | 어디에 | 왜 |
|---|---|---|
| recovery key 5조각 | 오프라인 (종이·오프라인 매체) | **재생성 불가** |
| 초기 root 토큰 | 오프라인 | 재발급에 recovery key 3조각 필요 |

### 봉투에 넣지 않는 것

복구 경로가 이미 있는 것을 봉투에 넣으면 봉투가 관리 부담만 된다.

| 시크릿 | 잃었을 때 |
|---|---|
| Proxmox API 토큰 | Proxmox UI 에서 재발급 → [7-1](#7-1-proxmox-토큰-재발급) |
| Tailscale auth key | admin 콘솔에서 재발급 → [7-2](#7-2-tailscale-키-재발급과-이름-충돌) |
| SSH 키 | 새로 만들고 공개키 재배포 |
| unseal 키 | **사람이 갖지 않는다.** KMS 에 있다 |

### 초기화 후 즉시

```bash
vault status | grep -E "Sealed|Seal Type|Initialized"
```

`Sealed false` / `Seal Type awskms` / `Initialized true` 여야 한다.
**사람이 unseal 하지 않았는데 `false`** 인 것이 요점이다. `true` 면 seal 설정이
반영되지 않았다 → [8절](#8-막힐-때)

---

## 3. 일상 — 셸을 작업 가능 상태로

```bash
export AWS_PROFILE=cntlp
export VAULT_ADDR="https://cntlp-aws-vault-01.<tailnet>.ts.net:8200"
vault login -method=userpass username=pneuma
source scripts/cntlp-env.sh
```

`cntlp-env.sh` 가 하는 일:

1. `VAULT_ADDR`·토큰 유효성 확인 — **폴백이 없다.** 없으면 여기서 멈춘다
2. SSH 개인키를 Vault 에서 당겨 **ssh-agent 메모리에만** 넣는다 (`-t 8h`)
3. `ANSIBLE_CONFIG` 고정, `PYTHONWARNINGS` 억제

토큰 TTL 과 `ssh-add -t` 가 같은 8시간이다. 다르면 한쪽이 살아 있는데 다른 쪽이
죽어 원인을 헷갈린다.

```bash
vault token lookup | grep -E "policies|ttl"   # 남은 시간 확인
ssh-add -l                                    # agent 에 키가 있는지
```

---

## 4. 백업 — raft 스냅샷

raft 데이터는 인스턴스 EBS 에 있다. **인스턴스를 잃으면 같이 잃는다.**

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
vault operator raft snapshot save "/tmp/vault-${TS}.snap"

BUCKET=$(terraform -chdir=terraform/aws/vault output -raw vault_snapshot_bucket)
aws s3 cp "/tmp/vault-${TS}.snap" "s3://${BUCKET}/${TS}.snap"
shred -u "/tmp/vault-${TS}.snap"    # 로컬 사본을 남기지 않는다
```

**스냅샷은 시크릿 전부를 담는다.** unseal 되지 않은 상태로 암호화돼 있지만
unseal KMS 키에 접근할 수 있는 주체에게는 평문과 같다. 버킷은 SSE-KMS 이고
90일 뒤 만료된다.

`shred` 를 쓰는 이유는 `rm` 이 내용을 지우지 않기 때문이다.

**아직 자동화하지 않았다.** 지금은 이 절차뿐이다. 최소한 다음 셋 전에 뜬다 —
`egress` destroy, 인스턴스 재생성, `terraform/vault` 의 정책 변경.

---

## 5. 복구 — 스냅샷에서 되살리기

전제: [전체 순서](#전체-순서)의 1~4번으로 **초기화되지 않은** Vault 가 서 있다.

```bash
vault operator init -recovery-shares=5 -recovery-threshold=3   # 새 키가 나온다
export VAULT_TOKEN="<새 root 토큰>"

BUCKET=$(terraform -chdir=terraform/aws/vault output -raw vault_snapshot_bucket)
aws s3 cp "s3://${BUCKET}/<타임스탬프>.snap" /tmp/restore.snap
vault operator raft snapshot restore -force /tmp/restore.snap
shred -u /tmp/restore.snap
```

⚠️ **restore 후 root 토큰과 recovery key 가 스냅샷 시점의 것으로 돌아간다.**
방금 `init` 으로 받은 새 키는 무효가 되므로, **스냅샷 시점의 봉투가 필요하다.**
봉투를 잃었으면 스냅샷도 못 쓴다 — 그래서 봉투가 recovery key 인 것이다.

KMS 키는 그대로여야 한다. 키를 잃었으면 스냅샷도 복호화되지 않는다.

복구 후 확인:

```bash
vault status | grep -E "Sealed|Seal Type"
vault kv list secret/onp
vault policy list
```

---

## 6. `egress` 를 지울 때 Vault 를 먼저 내린다

NAT Gateway 는 시간당 과금이라 안 쓸 때 지우는 것이 설계 의도다. 그런데
Vault 는 그 경로로만 tailnet 에 붙는다 → [1-1](#1-1-egress-스택-없이는-부트스트랩되지-않는다)

**내릴 때**

```bash
# 1. 스냅샷 (4절)
# 2. Vault 를 정지한다 — 뜬 채로 고립되면 "왜 안 되지" 로 시간을 쓴다
ansible -i ansible/inventories/aws/aws_ec2.yaml component_vault \
  -b -m systemd -a "name=vault state=stopped"
# 3. egress destroy
terraform -chdir=terraform/aws/egress destroy
```

**올릴 때**

```bash
terraform -chdir=terraform/aws/egress apply
ansible -i ansible/inventories/aws/aws_ec2.yaml component_vault \
  -b -m systemd -a "name=vault state=started"
tailscale status | grep vault          # 재조인 확인
vault status | grep -E "Sealed|Seal"   # auto-unseal 확인
```

tailnet 이름 뒤에 `-1` 이 붙었으면 [7-2](#7-2-tailscale-키-재발급과-이름-충돌).

---

## 7. 재발급

### 7-1. Proxmox 토큰 재발급

봉투에 없어도 되는 이유가 이 절차다.

1. Proxmox UI → Datacenter → Permissions → API Tokens
2. `terraform@pve!provisioning` 을 지우고 다시 만든다 (Privilege Separation 해제)
3. Vault 에 넣는다

```bash
vault kv put secret/onp/proxmox api_token='terraform@pve!provisioning=<uuid>' \
  endpoint='https://<host>:8006/'
```

`terraform/onp` 는 Vault 에서 읽으므로 코드 변경이 없다.

### 7-2. Tailscale 키 재발급과 이름 충돌

**VM 을 지워도 tailnet 디바이스는 남는다.** 새 인스턴스는 machine key 가 새것이라
같은 이름의 디바이스가 하나 더 생기고 Tailscale 이 뒤에 `-1` 을 붙인다.
그러면 메시 이름이 바뀌어 **Vault 의 TLS 도메인과 `api_addr` 이 어긋난다.**

1. Tailscale admin → Machines → 오프라인 `cntlp-aws-vault-01` 삭제
2. Keys → **ephemeral · 재사용 가능 · 태그 부여 권한**으로 재발급
3. Vault 에 넣고, 부트스트랩에는 환경변수로 준다

```bash
vault kv put secret/onp/tailscale auth_key='tskey-auth-...'
export CNTLP_TAILSCALE_AUTH_KEY='tskey-auth-...'   # Vault 가 아직 없을 때만
```

ephemeral 로 발급하면 오프라인이 된 디바이스를 Tailscale 이 스스로 지워서
이 문제가 애초에 생기지 않는다. `vpn-mesh` 롤이 이름 불일치를 검사해 멈춘다.

### 7-3. 인스턴스를 다시 만들 때

`user_data_replace_on_change = true` 라서 cloud-init 을 바꾸면 인스턴스가
교체되고 **raft 데이터가 사라진다.**

1. 스냅샷 ([4절](#4-백업--raft-스냅샷))
2. tailnet 디바이스 삭제 ([7-2](#7-2-tailscale-키-재발급과-이름-충돌))
3. EICE 가 꺼져 있으면 켠다 ([1-2](#1-2-메시에-들어가기-전-접근-수단이-eice-뿐이다))
4. `terraform -chdir=terraform/aws/vault apply`
5. [전체 순서](#전체-순서) 4번부터, 초기화 대신 [복구](#5-복구--스냅샷에서-되살리기)

KMS 키와 스냅샷 버킷은 `prevent_destroy` 라 남는다. 그래서 복구가 가능하다.

---

## 8. 막힐 때

| 증상 | 원인 | 확인 |
|---|---|---|
| ansible 이 호스트에 못 붙는다 | EICE 가 꺼져 있거나 aws CLI v1 | `aws --version` 이 `aws-cli/2.` 인지. `terraform -chdir=terraform/aws/network output eice_id` |
| 인벤토리가 호스트 0개 | 자격증명 또는 태그 불일치 | `aws sts get-caller-identity`. `ansible-inventory -i inventories/aws/aws_ec2.yaml --list` |
| `Seal Type shamir` | `vault.hcl` 의 seal 블록 미반영 | `journalctl -u vault -n 50`. **재부팅마다 사람이 필요해진다** |
| 모든 요청이 500 | 감사 로그를 쓸 수 없다 (디스크 만원) | `df -h /var/log`. 의도된 동작이다 → [1-4](#1-4-감사-로그가-차면-vault-가-멈춘다) |
| `tailscale cert` 실패 | tailnet HTTPS 가 꺼져 있다 | Tailscale admin → DNS → HTTPS Certificates |
| `x509: certificate has expired` | 갱신 타이머가 죽었다 | `systemctl status vault-cert-renew.timer` |
| `x509: unknown authority` | tailnet 이름이 바뀌었다 | `tailscale status`. `-1` 접미사 → [7-2](#7-2-tailscale-키-재발급과-이름-충돌) |
| tailnet 조인 실패 | NAT 경로가 없다 | `terraform -chdir=terraform/aws/egress output nat_gateway_id` |
| `no valid credential sources` | AWS 자격증명 | `aws sts get-caller-identity` |
| terraform 이 Vault 를 못 읽는다 | 토큰 만료 (8h) | `vault token lookup`. 다시 로그인 |
| AppRole 이 403 | 정책 경계 — 의도된 것일 수 있다 | `terraform/vault/policies/` 를 본다 |
| VM 에 containerd 가 깔렸다 | `!component_vault` 누락 | `site-prerequisites.yaml` 의 hosts 패턴 |

---

## 전체 순서

전제: `aws sts get-caller-identity` 성공. Tailscale auth key
(**ephemeral · 태그 부여 권한**) 준비. `network` 스택 apply 완료.

| # | 명령 | 확인 |
|---|---|---|
| 1 | `terraform -chdir=terraform/aws/egress apply` | `nat_gateway_id` 출력 |
| 2 | `terraform -chdir=terraform/aws/vault apply` | 인스턴스 running. `check` 블록 경고 없음 |
| 3 | `tailscale status \| grep vault` — 아직 안 보이는 게 정상 | 조인은 4번이 한다 |
| 4 | `ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-vault.yaml -e vault_awskms_key_id=$(terraform -chdir=../terraform/aws/vault output -raw vault_kms_key_id)` | `seal=awskms`, `initialized=false` |
| 5 | `vault operator init -recovery-shares=5 -recovery-threshold=3` | [2절](#2-초기화--한-번만-되돌릴-수-없다). **봉인** |
| 6 | `terraform -chdir=terraform/vault apply` | 정책 3개, AppRole 2개, 감사 장치 |
| 7 | `terraform -chdir=terraform/vault output -raw next_steps` 실행 | 계정·secret_id·시크릿 4개 |
| 8 | root 토큰 버리고 userpass 로 재로그인 | `vault token lookup` 의 policies |
| 9 | `terraform -chdir=terraform/onp` 를 Vault 경로로 전환 | `006` 의 검증 기준 8개 |

4번 전에 `CNTLP_TAILSCALE_AUTH_KEY` 를 export 해야 한다 — 그 시점에는 Vault 가
없으므로 손으로 준다. 축소 불가능한 secret-zero 는 **AWS 자격증명 하나**이고,
이 키는 Vault 가 선 뒤 `secret/onp/tailscale` 로 들어간다.
