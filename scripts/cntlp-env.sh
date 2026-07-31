#!/usr/bin/env bash
#
# 온프렘 terraform·ansible 을 돌릴 수 있는 상태로 셸을 만든다.
#
# ── 하는 일 ─────────────────────────────────────────────────────
#
# **Vault 가 필요 없는 것부터 한다.** 순서에 이유가 있다 — 아래 「AWS 를 먼저」.
#
# 1. ANSIBLE_CONFIG 을 고정한다. ansible.cfg 는 **cwd 에서만** 자동으로 읽히므로
#    이게 없으면 리포 루트에서 돌릴 때 roles_path 를 못 찾는다.
# 2. PYTHONWARNINGS=ignore. Proxmox 자체서명 인증서 때문에 urllib3 경고가
#    매 실행마다 화면을 덮어 정작 봐야 할 태스크 결과를 밀어낸다.
# 3. AWS 세션을 boto3 가 읽을 수 있는 환경변수로 옮긴다.
# 4. Vault 의 secret/onp/proxmox 토큰 **하나**를 인벤토리가 요구하는 **넷**으로
#    분해한다.
#      KV:      api_token = "terraform@pve!provisioning=<uuid>"
#               endpoint  = "https://<host>:8006/"
#      export:  PROXMOX_URL / PROXMOX_USER / PROXMOX_TOKEN_ID / PROXMOX_TOKEN_SECRET
# 5. Vault 의 secret/ssh/cntlp-private 를 **ssh-agent 메모리에만** 넣는다.
#    디스크를 거치지 않는다.
#
# ── AWS 를 Vault 보다 먼저 하는 이유 ────────────────────────────
#
# 이 스크립트는 온프렘 전용이 아니다. **AWS 플레이북도 이걸 source 한다** —
# playbooks/site-vault.yaml 이 AWS 동적 인벤토리와 EICE 터널을 쓰고, 그 둘 다
# 여기서 세우는 자격증명과 ANSIBLE_CONFIG 을 요구한다.
#
# Vault 게이트를 앞에 두면 **Vault 를 세우는 작업이 Vault 를 요구하게 된다.**
# 그래서 Vault 가 필요한 부분(4·5)만 게이트 뒤에 두고, 실패해도 앞의 셋은
# 이미 서 있게 한다. 온프렘 값은 그때 unset 된다 — 이전 source 의 값이
# 남아 "되는 것처럼 보이는" 상태를 만들지 않기 위해서다.
#
# ── 왜 tfvars 가 아니라 Vault 인가 ──────────────────────────────
#
# 2026-07-31 이전에는 이 스크립트가 terraform/onp/terraform.tfvars 에서
# 토큰을 뽑았다. 그 파일에 더는 토큰이 없다 — 시크릿을 Vault 한 곳으로
# 모았다 → tasks/doing/006_vault-setup.md
#
# **폴백을 두지 않는다.** Vault 가 안 닿으면 이 스크립트는 그냥 실패한다.
# tfvars 로 조용히 돌아가지 않는다. 폴백을 남기면 사람은 결국 쉬운 길로
# 가고, 이 작업이 없애려는 상태가 그대로 남는다 (같은 문서 8절).
#
# ── 왜 AppRole 이 아니라 사람 토큰인가 ──────────────────────────
#
# 여기서 읽는 것 둘 다 AppRole 로는 못 읽는다. 의도된 것이다.
#
#   secret/onp/proxmox        ansible-onp 정책에 없다. ansible 은 VM 을 만들지
#                             않는다 — 동적 인벤토리가 Proxmox API 를 쓰지만
#                             그건 워크스테이션에서 사람이 돌리는 일이다
#   secret/ssh/cntlp-private  어느 AppRole 에도 없다. 개인키는 사람의
#                             ssh-agent 로만 들어간다
#
# 그래서 먼저 로그인해야 한다:
#   vault login -method=userpass username=pneuma      (토큰 TTL 8h)
#
# terraform/onp 는 이 토큰을 그대로 써도 되고, terraform-onp AppRole 토큰을
# 따로 발급해 써도 된다 → terraform/onp/providers.tf
#
# ── 왜 스크립트여야 하나 ────────────────────────────────────────
#
# **ansible 이 자기 자신에게 해줄 수 없는 일이다.** 인벤토리 플러그인이
# `lookup('env', ...)` 로 값을 읽으므로, 값은 ansible 프로세스가 시작되기
# **전에** 환경에 있어야 한다. 플레이북 안으로 옮길 수 없다.
#
# 손으로 export 하면 넷 중 하나를 빠뜨렸을 때 인벤토리가 **에러 없이 호스트
# 0개**로 성공한다. 실패로 보이지 않아서 알아채기 어렵다 — 이 프로젝트가
# 반복해 밟은 함정이다.
#
# ── 하지 않는 일 ────────────────────────────────────────────────
#
# - **SSH 키를 파일로 내리지 않는다.** ssh-agent 메모리에만 넣는다. 파일로
#   쓰면 원본이 그대로 있는 상태에서 평문 사본이 하나 더 생긴다 — 시크릿을
#   한 곳으로 모으는 작업이 사본을 늘리는 꼴이다 (같은 문서 4절).
#   그래서 inventories/onp/group_vars/platform_onp.yml 에도
#   ansible_ssh_private_key_file 이 없다
# - **ssh-agent 를 띄우지 않는다.** 띄우면 source 할 때마다 개인키를 문
#   프로세스가 하나씩 늘어나고, 어느 것이 살아 있는지 아무도 모르게 된다
# - **GCP 는 다루지 않는다.** GCP_PROJECT 와 서비스 계정은 직접 세운다
#
# ── 사용법 ──────────────────────────────────────────────────────
#
# **source 로 불러야 한다.** 실행하면 자식 셸에서 export 하고 끝난다.
#   vault login -method=userpass username=pneuma
#   source scripts/cntlp-env.sh
#   cd ansible && ansible-playbook playbooks/site-workers.yaml --tags common

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "source 로 불러야 한다:  source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

# ssh-agent 키 수명. terraform/vault 의 token_ttl_hours 와 같아야 한다.
# 다르면 한쪽이 살아 있는데 다른 쪽이 죽어 원인을 헷갈린다 —
# "Vault 는 되는데 ssh 가 안 된다" 또는 그 반대가 된다.
: "${CNTLP_SSH_AGENT_TTL:=8h}"

# Vault 주소는 비밀이 아니다. 기본값을 두되 이미 세워져 있으면 존중한다.
: "${CNTLP_VAULT_ADDR:=https://cntlp-aws-vault-01.tail270b85.ts.net:8200}"

# 온프렘 값을 지운다. Vault 단계가 실패했을 때 부른다.
#
# **비워두는 것이 아니라 지운다.** 이전 source 에서 남은 값이 있으면 인벤토리가
# 그걸로 붙으려다 만료된 토큰으로 실패하거나, 더 나쁘게는 **에러 없이 호스트
# 0개**로 성공한다. 실패로 보이지 않는 그 형태가 이 리포가 반복해 밟은 함정이다.
_cntlp_env_clear_onp() {
  unset PROXMOX_URL PROXMOX_USER PROXMOX_TOKEN_ID PROXMOX_TOKEN_SECRET
  echo "      → PROXMOX_* 를 지웠다. 온프렘 인벤토리는 지금 쓸 수 없다." >&2
}

# ── AWS 자격증명을 boto3 가 읽을 수 있게 옮긴다 ─────────────────
#
# **`aws` CLI 가 되는데 ansible 이 안 되는 상태가 실제로 생긴다.**
#
# `aws login` 으로 로그인하면 자격증명이 ~/.aws/login/ 에 세션으로 저장되고
# ~/.aws/config 에 `login_session` 이 박힌다. ~/.aws/credentials 는 만들어지지
# 않는다. terraform 의 Go SDK 는 그 형식을 읽지만 **apt 로 깐 boto3 는 못
# 읽는다.** 그래서 terraform apply 는 성공하는데 AWS 동적 인벤토리만
# "Unable to locate credentials" 로 죽는다 — 같은 셸에서 한쪽만 되니
# 자격증명 문제로 보이지 않는다.
#
# `aws configure export-credentials` 가 세션을 표준 환경변수로 뱉어준다.
# 그걸 export 하면 boto3 가 env 체인으로 찾는다.
#
# 세션이므로 만료가 있다. 만료 시각을 찍어서 "어제는 됐는데" 를 막는다.
_cntlp_env_aws() {
  if ! command -v aws >/dev/null 2>&1; then
    echo "warn: aws CLI 가 없다. AWS 인벤토리와 EICE 터널을 쓸 수 없다." >&2
    echo "      ./scripts/bootstrap-workstation.sh 를 돌린다." >&2
    return 1
  fi

  local aws_env
  if aws_env="$(aws configure export-credentials --format env 2>/dev/null)" \
     && [[ -n "$aws_env" ]]; then
    eval "$aws_env"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    # 리전은 세션에 없다. 인벤토리와 backend.tf 가 쓰는 값과 같아야 한다.
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
    return 0
  fi

  # 멈추지 않는다. 온프렘 ansible 에는 AWS 가 필요 없다.
  # **terraform/onp 에는 필요하다** — 상태가 S3 에 있다 (backend.tf).
  echo "warn: AWS 자격증명을 내보내지 못했다. AWS 동적 인벤토리와" >&2
  echo "      terraform/onp 의 S3 백엔드가 실패한다.  aws login 을 먼저 한다." >&2
  return 1
}

_cntlp_env() {
  local repo
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  # ── Vault 와 무관한 것부터 세운다 ─────────────────────────────

  # ansible.cfg 는 cwd 에서만 자동으로 읽힌다. 어디서 돌려도 잡히게 고정한다.
  export ANSIBLE_CONFIG="${repo}/ansible/ansible.cfg"

  # Proxmox 자체서명 인증서 때문에 매 실행마다 urllib3 경고가 화면을 덮는다.
  # (ANSIBLE_PYTHON_WARNINGS 라는 설정은 없다. ansible 은 이 변수를 읽지 않는다)
  export PYTHONWARNINGS=ignore

  _cntlp_env_aws

  printf 'ANSIBLE_CONFIG=%s\n' "$ANSIBLE_CONFIG"
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    printf 'AWS 자격증명 설정됨 — 만료 %s\n' "${AWS_CREDENTIAL_EXPIRATION:-(없음)}"
  fi

  # ── 여기부터 Vault 가 필요하다 ────────────────────────────────
  #
  # 실패하면 온프렘 값을 unset 하고 1 을 낸다. 위에서 세운 AWS·ANSIBLE_CONFIG
  # 은 그대로 살아 있다 — AWS 작업은 계속 할 수 있어야 한다.

  if ! command -v vault >/dev/null 2>&1; then
    echo "vault CLI 가 없다. ./scripts/bootstrap-workstation.sh 를 돌린다." >&2
    _cntlp_env_clear_onp
    return 1
  fi

  export VAULT_ADDR="${VAULT_ADDR:-$CNTLP_VAULT_ADDR}"

  # **토큰이 있는지를 환경변수로 판단하지 않는다.**
  #
  # `vault login` 은 VAULT_TOKEN 을 export 하지 않는다 — 토큰 헬퍼
  # (~/.vault-token, 0600) 에 저장할 뿐이다. 환경변수만 보면 정상적으로
  # 로그인한 셸을 "토큰 없음" 으로 판단해서 PROXMOX_* 를 지워버린다.
  #
  # 그러면 ansible 인벤토리가 빈 URL 로 붙으려다 이렇게 죽는데, 원인이
  # 전혀 안 드러난다:
  #
  #   Invalid URL '/api2/json/nodes': No scheme supplied.
  #
  # terraform 의 vault provider 도 ansible 의 community.hashi_vault 도 둘 다
  # 헬퍼 파일을 폴백으로 읽는다. 그래서 여기서도 "값이 있나" 가 아니라
  # **"실제로 되나"** 를 본다. 만료·폐기도 같은 검사로 걸린다.
  if ! vault token lookup >/dev/null 2>&1; then
    echo "Vault 토큰이 없거나 유효하지 않다 (만료·폐기 포함)." >&2
    echo "  export VAULT_ADDR=$VAULT_ADDR" >&2
    echo "  vault login -method=userpass username=pneuma" >&2
    echo "  (VAULT_TOKEN 을 직접 export 해도 된다 — 둘 다 인식한다)" >&2
    _cntlp_env_clear_onp
    return 1
  fi

  # ── Proxmox 토큰을 넷으로 분해한다 ────────────────────────────

  local endpoint token
  endpoint="$(vault kv get -field=endpoint secret/onp/proxmox 2>/dev/null)"
  token="$(vault kv get -field=api_token secret/onp/proxmox 2>/dev/null)"

  if [[ -z "$endpoint" || -z "$token" ]]; then
    echo "secret/onp/proxmox 에서 endpoint 또는 api_token 을 못 읽었다." >&2
    echo "  vault kv get secret/onp/proxmox   로 확인한다." >&2
    _cntlp_env_clear_onp
    return 1
  fi

  # user@realm!tokenid=secret 을 셋으로 가른다.
  if [[ ! "$token" =~ ^([^!]+)\!([^=]+)=(.+)$ ]]; then
    echo "secret/onp/proxmox 의 api_token 이 형식에 안 맞는다." >&2
    echo "  user@realm!tokenid=uuid 여야 한다." >&2
    _cntlp_env_clear_onp
    return 1
  fi

  export PROXMOX_URL="$endpoint"
  export PROXMOX_USER="${BASH_REMATCH[1]}"
  export PROXMOX_TOKEN_ID="${BASH_REMATCH[2]}"
  export PROXMOX_TOKEN_SECRET="${BASH_REMATCH[3]}"

  # ── 개인키를 ssh-agent 메모리로 넣는다 ────────────────────────
  #
  # 파이프라서 디스크를 거치지 않는다. -t 로 agent 가 스스로 잊는다.
  # 같은 키를 다시 넣으면 교체되므로 재실행이 수명을 갱신한다.

  local ssh_ok=0
  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "warn: ssh-agent 가 없다. 개인키를 넣지 못했다." >&2
    echo "      eval \"\$(ssh-agent -s)\" 한 뒤 다시 source 한다." >&2
    echo "      terraform 의 snippets 업로드와 ansible 접속이 실패한다." >&2
  elif vault kv get -field=private_key secret/ssh/cntlp-private 2>/dev/null \
         | ssh-add -q -t "$CNTLP_SSH_AGENT_TTL" - 2>/dev/null; then
    ssh_ok=1
  else
    echo "warn: 개인키를 ssh-agent 에 넣지 못했다." >&2
    echo "      vault kv get secret/ssh/cntlp-private 이 되는지 본다." >&2
    echo "      AppRole 토큰으로는 이 경로를 읽을 수 없다 — 사람 토큰이어야 한다." >&2
  fi

  # 값은 절대 찍지 않는다. 무엇이 설정됐는지만 알린다.
  printf '온프렘 환경 설정 완료 — PROXMOX_URL=%s PROXMOX_USER=%s (토큰 2개 설정됨)\n' \
    "$PROXMOX_URL" "$PROXMOX_USER"
  printf 'VAULT_ADDR=%s\n' "$VAULT_ADDR"

  if [[ "$ssh_ok" -eq 1 ]]; then
    printf 'SSH 개인키를 ssh-agent 에 넣었다 (%s 뒤 자동 삭제, 디스크에 쓰지 않음)\n' \
      "$CNTLP_SSH_AGENT_TTL"
  fi
}

_cntlp_env
_cntlp_env_rc=$?
unset -f _cntlp_env _cntlp_env_aws _cntlp_env_clear_onp

# **반환값을 살려서 내보낸다.** source 의 종료 상태는 마지막 명령의 것이므로,
# 여기서 정리만 하고 끝내면 실패해도 늘 0 이 된다. 그러면
#   source scripts/cntlp-env.sh && ansible-playbook ...
# 가 PROXMOX_* 가 비어 있는 채로 이어지고, 인벤토리는 **에러 없이 호스트 0개**
# 로 성공한다 — 실패로 보이지 않는 그 형태다.
if [[ $_cntlp_env_rc -eq 0 ]]; then
  unset -v _cntlp_env_rc
  true
else
  unset -v _cntlp_env_rc
  false
fi
