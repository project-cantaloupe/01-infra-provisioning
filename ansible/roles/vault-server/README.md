# vault-server

Vault 서버를 설치하고 **초기화되지 않은 상태로** 세운다.

## 하는 일

1. HashiCorp apt 저장소 등록 — 키가 0바이트면 저장소를 등록하지 않고 멈춘다
2. `vault` 를 버전 고정으로 설치 (`vault_apt_version`)
3. `tailscale cert` 로 tailnet TLS 인증서 발급 + 주 1회 갱신 타이머
4. `vault.hcl` — raft 단일 노드 + awskms auto-unseal + TLS 리스너
5. 서비스 시작 후 **seal 타입이 awskms 인지** API 에 물어 확인

## 하지 않는 일

- **`vault operator init`.** recovery key 를 사람이 받아 오프라인에 봉인해야
  한다. 자동화하면 그 값이 ansible 로그나 파일에 남는다 — 이 롤이 없애려는
  문제를 이 롤이 만드는 셈이다. → `references/20260801_infra-05-vault-ops.md`
- **정책·auth·KV mount.** `terraform/vault/` 스택이 소유한다
- **tailnet 조인.** `vpn-mesh` 롤이 앞에서 한다. 이 롤은 결과만 읽는다
- **시크릿 투입.** 사람이 `vault` CLI 로 한다. terraform 이 하면 값이
  tfstate 에 평문으로 남는다
- **스냅샷 스케줄.** 아직 없다. 런북의 수동 절차뿐이다

## 왜 검증이 seal 타입까지 보는가

`systemctl is-active vault` 는 다음 셋 모두에서 `active` 다.

| 상태 | active? | 실제로 쓸 수 있나 |
|---|---|---|
| unsealed | 예 | 예 |
| sealed | 예 | **아니오** — 모든 API 가 503 |
| seal 블록 미반영 (shamir) | 예 | 지금은 되지만 **재부팅하면 멈춘다** |

세 번째가 가장 위험하다. 지금 동작하므로 성공으로 보이는데, 다음 재부팅에
사람이 없으면 Vault 가 조용히 죽어 있다. 그래서 `/v1/sys/seal-status` 의
`type` 이 `awskms` 인지 본다.

## 필수 입력

| 변수 | 어디서 |
|---|---|
| `vault_awskms_key_id` | `terraform -chdir=terraform/aws/vault output -raw vault_kms_key_id` |
| tailnet 조인 (vpn-mesh) | `CNTLP_TAILSCALE_AUTH_KEY` 환경변수 |

`vault_awskms_key_id` 가 비면 롤이 멈춘다. 없이 진행하면 shamir seal 로 서는데
위 표의 세 번째 상태가 된다.

## 전제

- **`egress` 스택이 apply 돼 있어야 한다.** Private Subnet 이라 NAT 없이는
  apt 도 tailnet 조인도 나가지 못한다
- **tailnet 에서 HTTPS 가 켜져 있어야 한다** (Tailscale admin → DNS → HTTPS
  Certificates). 안 켜져 있으면 `tailscale cert` 가 실패한다
- `vpn-mesh` 가 이 롤보다 먼저 돌아야 한다

## Vault 2.x

`vault_version` 기본값은 2.0.3 이다 (1.21.x 가 이전 라인).
`storage "raft"` · `listener "tcp"` · `api_addr` · `disable_mlock` 는 2.0 에서
그대로 유효한 것을 로컬에서 확인했다. `seal "awskms"` 는 AWS 자격증명이 있어야
확인되므로 5번 검증이 그 역할을 한다.

버전을 고정하는 이유는 **raft 가 다운그레이드를 허용하지 않기 때문**이다.
`state: latest` 로 두면 실행 시점마다 다른 버전이 깔리고 되돌릴 수 없다.
