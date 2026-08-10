# vault — Vault 내부 설정

Vault **안**의 mount·정책·auth·감사 장치를 소유한다.
AWS 자원은 만들지 않는다 — 그건 `terraform/aws/vault` 다.

## 전제

Vault 가 살아 있고 **초기화·unseal 돼 있어야** 한다.

```bash
export VAULT_ADDR="https://cntlp-aws-vault-01.<tailnet>.ts.net:8200"
export VAULT_TOKEN="<초기 root 토큰>"
vault status        # Sealed=false, Initialized=true
```

순서는 `references/20260801_infra-05-vault-ops.md` 가 갖는다.

## 순환을 어떻게 끊는가

Vault 를 설정하려면 Vault 토큰이 필요하다. **초기 root 토큰으로 1회 apply** 하는
것으로 끊는다. apply 후 root 토큰은 오프라인 봉투로 돌아가고, 이후 변경은
사람 정책(`policies/human.hcl`)을 가진 토큰으로 한다.

## 만드는 것

| 자원 | 무엇 |
|---|---|
| `vault_mount.secret` | KV v2, 버전 10개 보관 |
| `vault_policy` × 3 | `human.hcl` · `terraform-onp.hcl` · `ansible-onp.hcl` |
| `vault_auth_backend.userpass` | 사람. **Keycloak 오면 지운다** |
| `vault_auth_backend.approle` | 기계. role 2개 |
| `vault_audit.file` | 파일 감사 장치 |

## 만들지 않는 것 — 전부 같은 이유다

**tfstate 에 평문으로 남기 때문이다.**

| 안 만드는 것 | 대신 |
|---|---|
| 시크릿 값 (`vault_kv_secret_v2`) | 사람이 `vault kv put` |
| `secret_id` | 사람이 `vault write -f .../secret-id` |
| userpass 비밀번호 | 사람이 `vault write ... password=-` |

`terraform output next_steps` 가 명령을 그대로 뱉는다.

## 정책의 요점

`terraform-onp` 이 `secret/ssh/cntlp-private` 를 **읽지 못하는 것**이다.

KV v2 에는 필드 단위 ACL 이 없다. 공개키와 개인키를 한 경로에 두면
cloud-init 용 공개키를 읽는 주체가 개인키까지 읽고, 그러면 **VM 을 만들 권한이
모든 노드에 root 로 들어갈 권한이 된다.** 그래서 경로를 갈랐다.

apply 후 그 경계를 실제로 확인한다 — `next_steps` 의 5번.

## 감사 장치와 디스크

**감사 장치가 켜져 있으면 로그를 쓸 수 없을 때 Vault 가 요청을 거부한다.**
디스크가 차면 Vault 가 멈춘다는 뜻이고, 의도된 동작이다 — 감사 없이 시크릿을
내주지 않는다.

그래서 두 곳이 짝을 이룬다.

| 무엇 | 어디 |
|---|---|
| 감사 장치 켜기 | 이 스택 (`audit.tf`) — 초기화 후에만 가능해서 ansible 이 못 한다 |
| 로그 디렉터리·logrotate | `vault-server` 롤 — 초기화 전에 있어야 이 스택의 apply 가 성공한다 |

**경로가 두 곳에 적혀 있다.** `var.audit_log_path` 와 롤의
`vault_audit_log_path`. 한쪽만 바꾸면 Vault 는 A 에 쓰고 logrotate 는 B 를 돌아,
로그가 무한히 자라다 디스크를 채우고 그 순간 Vault 가 멈춘다.

## 적용

```bash
terraform -chdir=terraform/vault init
terraform -chdir=terraform/vault plan
terraform -chdir=terraform/vault apply
terraform -chdir=terraform/vault output -raw next_steps
```
