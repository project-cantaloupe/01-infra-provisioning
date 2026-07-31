# 04 — 시크릿을 넣고 쓰는 법

**새 비밀 값이 생겼을 때 어디에 어떻게 넣고, 코드에서 어떻게 읽는가.**

왜 이런 구조인지는 [01 §6](01_architecture.md#6-주체를-가른다--secret-zero-는-하나뿐),
Vault 서버 자체를 다루는 절차는 [05](05_vault-ops.md) 에 있다.

---

# 원칙 셋

무엇을 하기 전에 이 셋을 안다. 나머지는 전부 여기서 따라 나온다.

## 1. 경로를 먼저 정한다

값이 무엇이냐가 아니라 **누가 읽느냐**가 경로를 정한다.

**KV v2 에는 필드 단위 ACL 이 없다.** 한 경로를 읽을 수 있으면 그 안의 모든
필드를 읽는다. 그래서 배치를 잘못하면 나중에 못 가른다.

```
✗ secret/ssh/keys                   ← 한 경로에 뭉치면
    authorized_keys = ...              공개키를 읽어야 하는 terraform 이
    private_key     = ...              개인키까지 읽는다

✓ secret/ssh/cntlp-public           ← 읽는 주체가 다르면 경로도 다르다
✓ secret/ssh/cntlp-private
```

한 경로에 뭉쳤다면 **VM 을 만들 권한이 모든 노드에 root 로 들어갈 권한이 된다.**

새 시크릿을 넣기 전에 이 표를 한 줄 채워본다. **칸이 안 채워지면 경로가
잘못된 것이다.**

| 값 | 누가 읽나 | 누가 읽으면 안 되나 | 경로 |
|---|---|---|---|

## 2. 값은 사람이 넣는다. terraform 이 넣지 않는다

`vault_kv_secret_v2` **리소스**가 있지만 쓰지 않는다. 그 값이 tfstate 에
평문으로 들어가기 때문이다 — 시크릿을 한 곳에 모으려는 작업이 새 사본을
만드는 꼴이 된다.

terraform 이 소유하는 것은 **mount·정책·AppRole 까지**다. 값은 아니다.

## 3. 폴백을 만들지 않는다

Vault 가 안 닿으면 그냥 죽게 둔다. "Vault 를 먼저 보고 없으면 환경변수" 로
짜면 두 가지가 일어난다. 그 폴백이 동작하는 동안 **아무도 Vault 경로가 깨진
걸 모르고**, 평문 경로가 영원히 안 지워진다.

---

# 새 시크릿을 넣는 절차

예시로 `secret/aws/network` 에 `terraform/aws/network` 의 tfvars 값을 넣는다고
하자. (실제로 필요한 작업이다 — 그 tfvars 가 리포에 없어서 지금 그 스택을
apply 할 수 없다.)

### 1. 경로와 읽을 주체를 정한다

```
secret/aws/network
  enable_eice      = "true"
  vpc_cidr         = "10.x.x.x/16"
  eice_expires_on  = "2026-12-31"
```

읽는 주체 — 사람(`pneuma`)뿐. terraform 을 사람이 돌리므로 AppRole 이 필요
없다. **AppRole 이 필요해지는 것은 CI 가 붙을 때다.**

### 2. 정책에 줄을 넣는다

`pneuma` 는 `secret/data/*` 를 이미 읽으므로 이 예시는 정책 변경이 없다.
AppRole 에 주려면 `terraform/vault/policies/<이름>.hcl` 에 넣는다.

```hcl
path "secret/data/aws/network" {
  capabilities = ["read"]
}

# **metadata 도 같이 준다.** provider 가 KV 버전을 확인하려고 읽는데,
# 없으면 "unsupported path" 로 죽고 원인이 권한이라는 게 드러나지 않는다.
path "secret/metadata/aws/network" {
  capabilities = ["read"]
}
```

> KV v2 는 경로가 둘로 갈린다. 실제 값은 `secret/data/<경로>`,
> 버전 이력과 소프트 삭제는 `secret/metadata/<경로>` 다.
> **`secret/<경로>` 는 CLI 가 쓰는 표기이고 정책에는 그렇게 적지 않는다.**

### 3. 정책을 적용한다 — root 토큰이 필요하다

```bash
export VAULT_ADDR=https://cntlp-aws-vault-01.<tailnet>.ts.net:8200
export VAULT_TOKEN='<봉투의 초기 root 토큰>'
terraform -chdir=terraform/vault apply
```

**`pneuma` 정책으로는 안 된다.** 자기 권한을 스스로 넓힐 수 없게 만들어져
있다. 의도된 제약이고, 그래서 정책 변경은 봉투를 여는 일이 된다.

끝나면 root 토큰을 버린다.

```bash
unset VAULT_TOKEN
vault login -method=userpass username=pneuma
```

### 4. 값을 넣는다 — 셸 히스토리에 안 남게

값을 명령줄에 직접 쓰면 셸 히스토리와 `/proc` 에 남는다. 셋 중 하나를 쓴다.

```bash
# 파일에서: @ 를 쓴다
vault kv put secret/ssh/cntlp-public authorized_keys=@~/.ssh/cantaloupe_ed25519.pub

# 손으로 입력: - 를 쓰면 stdin 에서 읽는다
vault kv put secret/aws/network enable_eice=-

# 여러 필드를 한 번에: 셸 변수를 거친다
CIDR=$(cat /path/to/value)
vault kv put secret/aws/network vpc_cidr="$CIDR" enable_eice=true
```

> ⚠️ **한 경로에 `put` 하면 그 경로가 통째로 교체된다.** 필드 하나만 바꾸려면
> `patch` 를 쓴다 — `vault kv patch secret/aws/network enable_eice=false`.
> `put` 으로 한 필드만 주면 **나머지 필드가 사라진다.** 이 종류 작업의 흔한
> 사고다.

### 5. 확인한다 — 값을 화면에 찍지 않고

```bash
# 필드 이름만
vault kv get -format=json secret/aws/network | jq '.data.data | keys'

# 값 하나만 길이로
vault kv get -field=vpc_cidr secret/aws/network | wc -c

# 경계 확인: 못 읽어야 하는 주체로 시도
VAULT_TOKEN=$APPROLE_TOKEN vault kv get secret/aws/network   # 403 이어야 한다
```

**경계 확인을 생략하지 않는다.** 정책을 너무 넓게 쓴 실수는 아무 에러도 내지
않는다.

---

# 코드에서 읽는 법

## Terraform — ephemeral 인가 data 인가

**이 판단이 가장 중요하다.**

| | `ephemeral` | `data` |
|---|---|---|
| state 에 남나 | **안 남는다** | **평문으로 남는다** |
| plan 파일에 남나 | 안 남는다 | 남는다 |
| 어디에 쓸 수 있나 | provider 설정, 다른 ephemeral | 아무 데나 |
| 언제 쓰나 | **비밀** | 비밀 아닌 값 |

```hcl
# 비밀 — provider 설정으로만 흘린다. state 에 안 남는다.
ephemeral "vault_kv_secret_v2" "proxmox" {
  mount = "secret"
  name  = "onp/proxmox"
}

provider "proxmox" {
  endpoint  = ephemeral.vault_kv_secret_v2.proxmox.data["endpoint"]
  api_token = ephemeral.vault_kv_secret_v2.proxmox.data["api_token"]
}

# 비밀이 아닌 값 — 자원 인자로 들어가야 하므로 data 를 쓴다.
data "vault_kv_secret_v2" "ssh_public" {
  mount = "secret"
  name  = "ssh/cntlp-public"
}
```

**ephemeral 값은 일반 자원의 인자로 못 간다.** terraform 이 막는다 — 그래서
실수로 state 에 새는 경로가 없다.

여기서 판단이 갈린다. 자원 인자로 넣어야 하는 값이면 `data` 를 써야 하고,
**그건 state 에 남는다는 뜻이므로 비밀이면 안 된다.** 값이 비밀인데 자원
인자로 들어가야 한다면 설계가 잘못된 것이다. 그 값을 terraform 이 아니라
다른 곳에서 주입할 방법을 찾는다(cloud-init 이 부팅 시 Vault 에서 직접 읽게
하는 식).

provider 설정은 이렇게 시작한다.

```hcl
provider "vault" {
  # VAULT_ADDR / VAULT_TOKEN 을 읽는다. 코드에 넣지 않는다.
  # 자식 토큰을 만들지 않는다 — auth/token/create 를 정책에 넣지 않기 위해서.
  skip_child_token = true
}
```

## Ansible

```yaml
# inventories/<영역>/group_vars/<그룹>.yml
tailscale_auth_key: >-
  {{ lookup('community.hashi_vault.vault_kv2_get', 'onp/tailscale').secret.auth_key }}
```

셋을 알아둔다.

- 경로에서 `secret/` 접두사를 **빼고** 쓴다. mount 가 기본값 `secret` 이다
- 반환값의 `.secret` 이 실제 필드 딕셔너리다 (`.data` 가 아니다)
- **jinja 는 지연 평가된다.** 그 변수를 쓰는 태스크가 실행될 때만 Vault 를
  부른다. 조건부로 건너뛰는 태스크면 Vault 가 없어도 플레이북이 돈다

인증은 `VAULT_ADDR`/`VAULT_TOKEN` 환경변수 또는 `~/.vault-token` 이다.
`scripts/cntlp-env.sh` 가 세운다 → [03 §4](03_onboarding.md#4-환경을-세우고-확인한다).

`no_log: true` 를 값 다루는 태스크에 건다. **assert 에는 걸지 않는다** —
값이 아니라 표현식만 찍고, `fail_msg` 가 사람에게 필요한 안내다.

## 셸 / 스크립트

```bash
# 파이프로만. 파일로 내리지 않는다.
vault kv get -field=private_key secret/ssh/cntlp-private | ssh-add -q -t 8h -
```

`ssh-add -t` 로 수명을 주는 것이 핵심이고, **Vault 토큰 TTL 과 같은 8h** 를
쓴다. 다르면 한쪽이 살아 있는데 다른 쪽이 죽어 원인을 헷갈린다.

## K8s (아직 없음)

External Secrets Operator 로 `secret/` 를 K8s Secret 으로 동기화할 예정이고,
그건 `repos/02-k8s-manifests` 가 갖는다. 클러스터 안에서는 이 문서가 아니라
그쪽을 본다.

---

# 회전

값을 새것으로 바꾸는 절차다. Vault 인스턴스 자체를 다시 만드는 것은
[05 §7](05_vault-ops.md#7-인스턴스를-다시-만들-때) 이다.

## Proxmox 토큰

```bash
# 1. Proxmox 에서 새로 발급 (UI → Datacenter → Permissions → API Tokens)
pveum user token add terraform@pve provisioning --privsep 0

# 2. Vault 를 갱신. put 이므로 두 필드 다 준다
vault kv put secret/onp/proxmox \
  api_token='terraform@pve!provisioning=<새 uuid>' \
  endpoint='https://<host>:8006/'

# 3. 확인 — 새 값으로 실제로 되는가
source scripts/cntlp-env.sh
terraform -chdir=terraform/onp plan     # No changes 여야 한다
```

**옛 토큰을 Proxmox 에서 지우는 것은 3번 확인 뒤에 한다.** 순서를 바꾸면 새
값이 틀렸을 때 되돌릴 수단이 없다.

`terraform/onp` 는 Vault 에서 읽으므로 코드 변경이 없다.

## Tailscale 키

```bash
vault kv put secret/onp/tailscale auth_key='tskey-auth-<새 키>'
```

**reusable + 해당 태그 부여 권한 + ephemeral** 로 발급한다. ephemeral 이
중요한 이유는 VM 을 다시 만들 때다 — 같은 이름의 죽은 디바이스가 tailnet 에
남으면 Tailscale 이 뒤에 `-1` 을 붙여 메시 이름이 달라진다
(→ [07 §2-2](07_onp-vm-recreate.md#2-2-tailnet-디바이스도-vm-을-지워도-남는다)).

## SSH 키

키를 새로 만들면 **공개키 배포가 따라온다.** 노드에 이미 들어간 옛 공개키는
Vault 를 갱신해도 안 바뀐다.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/cantaloupe_new -C cantaloupe-infra
vault kv put secret/ssh/cntlp-public  authorized_keys=@~/.ssh/cantaloupe_new.pub
vault kv put secret/ssh/cntlp-private private_key=@~/.ssh/cantaloupe_new

# 새 VM 부터 새 키가 들어간다. 기존 노드는 ansible 로 밀어넣는다.
```

후속 태스크의 SSH CA 로 전환하면 이 배포 문제 자체가 사라진다.

## 잘못 넣었을 때

KV v2 는 버전 이력을 10개까지 갖는다.

```bash
vault kv metadata get secret/onp/proxmox        # 버전 목록
vault kv get -version=3 secret/onp/proxmox      # 옛 버전 읽기
vault kv rollback -version=3 secret/onp/proxmox # 되돌리기
```

---

# 지금 있는 경로

| 경로 | 필드 | `terraform-onp` | `ansible-onp` | 사람 |
|---|---|---|---|---|
| `secret/onp/proxmox` | `api_token`, `endpoint` | 읽음 | **403** | 전부 |
| `secret/onp/tailscale` | `auth_key` | **403** | 읽음 | 전부 |
| `secret/ssh/cntlp-public` | `authorized_keys` | 읽음 | 읽음 | 전부 |
| `secret/ssh/cntlp-private` | `private_key` | **403** | **403** | 전부 |

**개인키는 어느 자동화 주체도 못 읽는다.** 사람의 ssh-agent 로만 들어간다.

넣지 않는 것 둘 —

- **kubeadm join 토큰.** 24시간 만료의 생성물이다. `kubeadm token create` 로
  필요할 때 만드는 것이 이미 맞는 방식이다
- **RDS 마스터 비밀번호.** AWS Secrets Manager 가 갖고 RDS 가 자동 회전한다.
  Vault 로 가져오면 그 이점을 잃는다

---

# 감사 — 누가 무엇을 꺼냈나

```bash
ssh ubuntu@cntlp-aws-vault-01 \
  'sudo grep cntlp-private /var/log/vault/audit.log | tail -5 | jq -r
     "[.auth.display_name, .request.path, (.error // \"성공\")] | @tsv"'
```

주체가 갈려 나온다 — `userpass-pneuma`, `approle`, `token-terraform`, `root`.
**거부도 정책 이름과 함께 남는다.**

```
[default,terraform-onp] secret/data/ssh/cntlp-private   permission denied
[ansible-onp,default  ] secret/data/onp/proxmox         permission denied
```

> **감사 로그를 쓸 수 없으면 Vault 가 모든 요청을 거부한다.** 의도된 동작이다 —
> 감사 없이 시크릿을 내주지 않는다. 단일 노드라 우회 경로가 없으므로 디스크가
> 차지 않는지 사람이 본다 → [05 §1-4](05_vault-ops.md#1-4-감사-로그가-차면-vault-가-멈춘다)

---

# 하지 말 것

| 하지 말 것 | 왜 |
|---|---|
| `vault_kv_secret_v2` **리소스**로 값 넣기 | tfstate 에 평문으로 남는다 |
| 비밀을 `data` 로 읽어 자원 인자에 쓰기 | 같은 이유. `ephemeral` 을 쓴다 |
| 한 경로에 읽는 주체가 다른 값 뭉치기 | 필드 단위 ACL 이 없다 |
| Vault 실패 시 환경변수로 폴백 | 깨진 걸 아무도 모르게 된다 |
| `put` 으로 필드 하나만 갱신 | 나머지 필드가 사라진다. `patch` 를 쓴다 |
| 개인키를 파일로 내리기 | 원본이 있는 상태에서 사본이 하나 는다 |
| `secret/<경로>` 를 정책에 적기 | `secret/data/` 와 `secret/metadata/` 로 적는다 |
| 값을 명령줄 인자로 직접 주기 | `/proc` 와 셸 히스토리에 남는다. `@파일`·`-`·변수를 쓴다 |
