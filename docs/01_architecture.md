# 01 — 아키텍처: 왜 이 모양인가

**처음 온 사람이 가장 먼저 읽는 문서.** 여기에는 절차가 없다. 왜 이렇게
생겼는지만 적는다. 세우는 순서는 [02](02_build-order.md) 에 있다.

각 절은 **"안 하면 어떻게 되는가"** 로 끝난다. 그게 그 선택의 이유다.

---

## 1. 전체 모양

세 영역에 흩어진 노드가 **하나의 Kubernetes 클러스터**를 이룬다.
물리 위치는 노드 라벨로만 구분한다.

```
                    Tailscale 메시 (tailnet)
  ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈

   AWS                   GCP                온프렘 (Proxmox)
   ───                   ───                ────────────────
   cntlp-aws-cp-01       cntlp-gcp-wk-01    cntlp-onp-wk-01
   cntlp-aws-wk-01       cntlp-gcp-wk-02
   cntlp-aws-vault-01
```

| 노드 | `role` 라벨 | 무엇을 올리나 |
|---|---|---|
| `cntlp-aws-cp-01` | `control-plane` | K8s 컨트롤플레인 |
| `cntlp-aws-wk-01` | `service` | 서비스 워크로드 |
| `cntlp-gcp-wk-01` | `monitoring` | 모니터링 스택 |
| `cntlp-gcp-wk-02` | `logging` | 로깅 스택 |
| `cntlp-onp-wk-01` | `devops` | CI, 레지스트리 |
| `cntlp-aws-vault-01` | **없음** | 시크릿 저장소. K8s 노드가 아니다 |

**인터넷에 노출되는 것은 오디오 앱뿐이다.** SSH, K8s API, 각종 UI —
나머지는 전부 메시 안쪽이라 tailnet 에 들어와야 보인다.

Vault 노드에 `role` 이 없는 이유는 그게 K8s 노드 전용 라벨이라서다. 대신
`component=vault` 태그가 붙고, 플레이북이 `!component_vault` 로 제외한다
(→ [05 §1-3](05_vault-ops.md#1-3-k8s-노드가-아니다)).

---

## 2. 이 설계가 풀려는 문제

AWS·GCP·온프렘 세 영역의 시크릿이 워크스테이션 로컬에 흩어져 있었다.

| 시크릿 | 도입 전 | 도입 후 |
|---|---|---|
| Proxmox API 토큰 | `terraform/onp/terraform.tfvars` | `secret/onp/proxmox` |
| Tailscale auth key | 손으로 `export` | `secret/onp/tailscale` |
| SSH 개인키 | `~/.ssh/cantaloupe_ed25519` | `secret/ssh/cntlp-private` → ssh-agent |
| SSH 공개키 | tfvars 에 나열 | `secret/ssh/cntlp-public` |
| kubeadm join 토큰 | 손으로 `export` | **넣지 않는다** — 24h 짜리 생성물이다 |
| AWS 자격증명 | `aws login` 세션 | **넣지 않는다** — 아래 [6절](#6-주체를-가른다--secret-zero-는-하나뿐) |

목표는 저장 위치를 옮기는 것이 아니라 **누가 무엇을 꺼냈는지 남기는 것**이다.
그래서 감사 장치와 주체 분리가 이 설계의 절반을 차지한다.

---

## 3. 왜 Vault 가 클러스터 밖 EC2 인가

처음 계획은 Vault 를 `02-k8s-manifests/platform/aws/vault/` 에 두는 것이었다.
**성립하지 않는다.**

```
클러스터를 세우려면    Proxmox 토큰 · Tailscale 키 · SSH 키가 필요하다
그 시크릿을 주는 것이   클러스터 안의 Vault
```

클러스터 안의 Vault 는 **클러스터를 만드는 시크릿을 줄 수 없다.**
게다가 SSH 접속이 그 Vault 에 의존하면, 클러스터가 죽었을 때 노드에 들어가
고칠 수단까지 같이 사라진다.

그래서 `terraform/aws/vault/` 가 AWS 다섯 번째 스택으로 붙는다.
`network` · `egress` · `compute` · `database` 와 나란히 있고 상태도 따로 둔다
(`aws/vault/terraform.tfstate`). Vault 는 클러스터보다 먼저 서고 나중까지
남아서 `compute` 와 생애가 다르기 때문이다.

**안 하면** — 클러스터를 세우는 데 필요한 시크릿을 클러스터가 뜬 뒤에야 꺼낼
수 있는 순환에 갇힌다.

---

## 4. 네트워크 — 8200 을 열지 않는다

```
인터넷 ──✕──▶ Vault            Security Group 인바운드 = EICE SSH 1개
                                퍼블릭 IP 없음, Private Subnet

사람    ──▶ tailnet ──▶ Vault:8200     WireGuard 터널 안
ansible ──▶ EICE    ──▶ Vault:22       메시 진입 전 유일한 경로
Vault   ──▶ NAT     ──▶ 인터넷          apt · Tailscale 좌표 서버 · KMS · S3
```

### 8200 ingress 규칙을 넣어도 아무 효과가 없다

tailnet 트래픽은 WireGuard 로 캡슐화돼 `tailscale0` 인터페이스에 도착한다.
Security Group 이 보는 것은 8200/tcp 가 아니라 UDP 위의 암호화된 페이로드다.
**그래서 8200 규칙은 애초에 걸리지 않고, 넣어두면 인터넷에 열어둔 것으로
오해된다.**

UDP 41641(WireGuard 직접 연결)도 열지 않는다. 없으면 Tailscale 이 DERP
릴레이로 폴백해서, 동작은 하고 지연만 조금 는다. `cluster` Security Group 도
같은 선택이다.

### NAT 를 쓰되 떼어낼 수 있게 둔다

Private Subnet 이라 아웃바운드가 NAT Gateway 를 지난다. NAT 는 시간당
과금이라 `egress` 를 **destroy 할 수 있는 별도 스택**으로 분리해 두었다.

대가가 있다. **`egress` 를 지우면 Vault 가 좌표 서버로 나가지 못해 tailnet 에서
떨어지고, 접근 경로가 메시뿐이라 그대로 고립된다.** 인스턴스는 살아 있는데
아무도 닿을 수 없다.

`terraform/aws/vault/data.tf` 의 `check` 블록이 apply 때 NAT 경로를 검사하고,
내리고 올리는 순서는
[05 §6](05_vault-ops.md#6-egress-를-지울-때-vault-를-먼저-내린다) 에 있다.

**안 하면** — 퍼블릭 IP 를 붙이거나 8200 을 열게 되고, "인터넷에 노출하는
것은 오디오 앱뿐" 이라는 제약이 그 순간 깨진다.

---

## 5. seal — 열쇠를 KMS 에 맡기는 이유

Vault 는 켜질 때 **sealed** 상태다. 모든 API 가 503 을 낸다.

기본 방식(shamir)은 사람이 recovery key 조각을 임계값만큼 넣어 여는 것이고,
그건 **재부팅마다 사람이 필요하다**는 뜻이다. EC2 는 하드웨어 문제로 알아서
재시작된다. 그때 아무도 없으면 Vault 는 조용히 죽어 있다.

`seal "awskms"` 는 그 열쇠를 KMS 에 맡긴다. 인스턴스 프로파일이 그 키에
`Decrypt` 권한을 가지므로 부팅하면 스스로 unseal 한다.

| | shamir | awskms |
|---|---|---|
| 재부팅 후 | 사람이 unseal | **자동** |
| 사람이 받는 키 | unseal key | **recovery key** (rekey·root 재발급 전용) |
| 잃으면 | 데이터 손실 | KMS 키를 잃으면 데이터 손실 |

그래서 초기화 명령이 `-key-shares` 가 아니라 **`-recovery-shares`** 다.
한 번만 할 수 있는 일이라 틀리면 되돌릴 수 없다
(→ [05 §2](05_vault-ops.md#2-초기화--한-번만-되돌릴-수-없다)).

### 검증이 seal 타입까지 보는 이유

`systemctl is-active vault` 는 **세 상태 모두에서 `active`** 다.

| 상태 | active? | 쓸 수 있나 |
|---|---|---|
| unsealed | 예 | 예 |
| sealed | 예 | 아니오 — 전부 503 |
| seal 블록 미반영 (shamir) | 예 | **지금은 되고 재부팅하면 멈춘다** |

세 번째가 가장 위험하다. 지금 동작하므로 성공으로 보인다. `vault-server`
롤이 `/v1/sys/seal-status` 의 `type` 까지 확인하는 이유다.

**안 하면** — 어느 새벽 EC2 가 재시작하고, 아침이 "Vault 가 죽었다" 로 시작한다.

---

## 6. 주체를 가른다 — secret-zero 는 하나뿐

### 창구 두 개

| 창구 | 주체 | 토큰 수명 | 왜 |
|---|---|---|---|
| `userpass` | 사람 | 8h | **임시** — Keycloak OIDC 가 오면 지운다 |
| `approle` | Terraform · Ansible | 1h | `role_id`(공개) + `secret_id`(비밀) |

AppRole 이 값 둘로 나뉜 것은 **배달 경로를 가를 수 있어서**다. `role_id` 는
코드나 CI 설정에 적어도 되고 `secret_id` 만 비밀로 다룬다. 한쪽이 새어도
열리지 않는다.

창구를 가르면 감사 로그에서 주체가 구분된다. "누가 Proxmox 토큰을 꺼냈지?"
에 `userpass-pneuma` 와 `approle` 이 다른 줄로 남는다. root 토큰을 계속 쓰면
전부 한 줄로 뭉개져서, 이 프로젝트가 없애려는 문제가 그대로 남는다.

### 정책의 요점은 "못 읽는 것"

| 주체 | 읽는다 | **못 읽는다** |
|---|---|---|
| 사람 | 전부 (쓰기 포함) | — |
| `terraform-onp` | `onp/proxmox`, `ssh/cntlp-public` | **개인키, tailscale 키** |
| `ansible-onp` | `onp/tailscale`, `ssh/cntlp-public` | **개인키, proxmox 토큰** |

**공개키와 개인키가 다른 경로인 것이 이 표를 성립시킨다.** KV v2 에는 필드
단위 ACL 이 없어서, 한 경로를 읽을 수 있으면 그 안의 모든 필드를 읽는다.
한 경로에 뭉치면 cloud-init 에 넣을 공개키를 읽는 terraform 이 개인키까지
읽고, 그러면 **VM 을 만들 권한이 모든 노드에 root 로 들어갈 권한이 된다.**

경로를 설계하는 법은 [04 §1](04_secrets.md#1-경로를-먼저-정한다) 에 있다.

### 축소 불가능한 secret-zero 는 AWS 자격증명 하나

Vault 를 만드는 것이 그 자격증명이므로 Vault 안에 넣을 수 없다.

한때 둘이라고 봤다 — Vault EC2 자신의 Tailscale auth key. **EICE 덕분에
아니다.** `network` 스택의 EC2 Instance Connect Endpoint 로 ansible 이 메시
밖에서 붙을 수 있어서, cloud-init 에 auth key 를 심을 이유가 없다. 심었다면
그 값이 tfstate 와 인스턴스 메타데이터에 평문으로 남았을 것이다.

Tailscale 키는 Vault 를 **처음 세울 때만** 사람이 손으로 준다. 그 뒤로는
`secret/onp/tailscale` 에서 나온다.

**안 하면** — 감사 로그가 전부 `root` 한 줄이 되고, 시크릿을 옮긴 의미가
절반 사라진다.

---

## 7. 폴백을 두지 않는다

Vault 가 안 닿으면 terraform 과 ansible 이 **그냥 죽는다.** 환경변수나
tfvars 로 조용히 되돌아가지 않는다.

폴백을 남기면 사람은 결국 쉬운 길로 가고, 평문 경로가 살아 있는 한 이
작업이 없애려는 상태가 그대로 남는다. 게다가 폴백이 동작하는 동안에는
**Vault 경로가 깨진 것을 아무도 모른다.**

대신 오프라인 봉투에 **둘만** 넣는다.

| 봉인 | 왜 |
|---|---|
| recovery key 5조각 (임계값 3) | 재생성 불가 |
| 초기 root 토큰 | 재발급에 recovery key 3조각이 필요하다 |

Proxmox 토큰·Tailscale 키·SSH 키는 넣지 않는다. 재발급 경로가 이미 있어서
([04 회전](04_secrets.md#회전)) 봉투에 넣으면 관리 부담만 는다.

---

## 8. tfstate 가 시크릿을 복제하는 문제 — 어떻게 풀었나

Terraform **data source** 의 결과는 상태 파일에 평문으로 저장된다.
`sensitive = true` 는 화면 출력만 가리고 state 는 가리지 않는다.

```hcl
data "vault_kv_secret_v2" "proxmox" { ... }   # 값이 tfstate 로 들어간다
```

그대로 두면 Proxmox 토큰이 tfvars 에서 사라지는 대신 tfstate 에 나타난다.
**시크릿을 한 곳으로 모으는 작업이 새 사본을 만드는 셈이다.**

Terraform 1.10 의 **`ephemeral` 자원**이 이걸 없앤다. ephemeral 값은 state
에도 plan 파일에도 저장되지 않고 apply 도중에만 메모리에 존재한다.

```hcl
ephemeral "vault_kv_secret_v2" "proxmox" {   # state 에 안 남는다
  mount = "secret"
  name  = "onp/proxmox"
}
```

대신 제약이 붙는다. **ephemeral 값은 일반 자원의 인자로 못 간다.** provider
설정과 다른 ephemeral 값에만 흘릴 수 있다. 덕분에 실수로 state 에 새는
경로가 아예 없다. 어느 쪽을 쓸지 고르는 기준은
[04 「ephemeral 인가 data 인가」](04_secrets.md#terraform--ephemeral-인가-data-인가)
에 있다.

같이 필요했던 것이 상태 파일 자체의 암호화다. `backend.tf` 의
`encrypt = true` 만으로는 SSE-S3 이고, `kms_key_id` 를 명시해야 SSE-KMS 가
된다. 여덟 스택 전부에 넣었다
→ [06 §5](06_tfstate.md#5-backendtf-에-kms_key_id-가-없으면-전부-되돌아간다).

**안 하면** — Vault 를 붙이는 행위 자체가 평문 사본을 하나 더 만든다.
