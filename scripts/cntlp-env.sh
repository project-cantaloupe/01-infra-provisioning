#!/usr/bin/env bash
#
# 온프렘 ansible 을 돌릴 수 있는 상태로 셸을 만든다.
#
# ── 하는 일 ─────────────────────────────────────────────────────
#
# 1. tfvars 의 Proxmox 토큰 **하나**를 인벤토리가 요구하는 **넷**으로 분해한다.
#      tfvars:  proxmox_endpoint  = "https://<host>:8006/"
#               proxmox_api_token = "terraform@pve!provisioning=<uuid>"
#      export:  PROXMOX_URL / PROXMOX_USER / PROXMOX_TOKEN_ID / PROXMOX_TOKEN_SECRET
# 2. ANSIBLE_CONFIG 을 고정한다. ansible.cfg 는 **cwd 에서만** 자동으로 읽히므로
#    이게 없으면 리포 루트에서 돌릴 때 roles_path 를 못 찾는다.
# 3. PYTHONWARNINGS=ignore. Proxmox 자체서명 인증서 때문에 urllib3 경고가
#    매 실행마다 화면을 덮어 정작 봐야 할 태스크 결과를 밀어낸다.
#
# ── 왜 스크립트여야 하나 ────────────────────────────────────────
#
# **ansible 이 자기 자신에게 해줄 수 없는 일이다.** 인벤토리 플러그인이
# `lookup('env', ...)` 로 값을 읽으므로, 값은 ansible 프로세스가 시작되기
# **전에** 환경에 있어야 한다. 플레이북 안으로 옮길 수 없다.
#
# 그리고 tfvars 를 단일 출처로 유지하기 위한 형식 변환기다. terraform 과
# ansible 이 같은 토큰을 쓰는데 요구 형식이 다르다. ansible 쪽에 토큰을 또
# 적어두면 두 곳이 조용히 어긋난다.
#
# 손으로 export 하면 넷 중 하나를 빠뜨렸을 때 인벤토리가 **에러 없이 호스트
# 0개**로 성공한다. 실패로 보이지 않아서 알아채기 어렵다 — 이 프로젝트가
# 반복해 밟은 함정이다.
#
# ── 하지 않는 일 ────────────────────────────────────────────────
#
# - **SSH 키 경로를 내보내지 않는다.** 기본값 `~/.ssh/cantaloupe_ed25519` 는
#   inventories/onp/group_vars/platform_onp.yml 이 이미 갖고 있다.
#   CNTLP_SSH_KEY 는 그 기본값을 **덮으려는** 사람이 직접 쓰는 변수다.
# - **terraform 에는 아무 영향이 없다.** terraform 은 tfvars 를 직접 읽는다.
# - **온프렘 전용이다.** AWS·GCP 인벤토리는 다른 자격증명(AWS 자격증명,
#   GCP_PROJECT)을 요구하는데 여기서 다루지 않는다.
#
# ── 인벤토리가 tfvars 를 직접 읽게 하지 않는 이유 ───────────────
#
# 가능하다. 인벤토리 설정에서도 jinja 가 평가되므로
# `lookup('file', ...) | regex_search(...)` 로 뽑을 수 있다. 그런데
#   - `lookup('file')` 의 상대경로는 **인벤토리 파일이 아니라 cwd 기준**이다.
#     위에 적은 "0 hosts matched" 함정을 새로 하나 만드는 셈이다
#   - 토큰이 인벤토리 설정에 템플릿되면 `-vvv` 로 노출될 수 있다.
#     이 스크립트는 값을 절대 찍지 않는다
#
# ── 사용법 ──────────────────────────────────────────────────────
#
# **source 로 불러야 한다.** 실행하면 자식 셸에서 export 하고 끝난다.
#   source scripts/cntlp-env.sh
#   cd ansible && ansible-playbook playbooks/site-workers.yaml --tags common

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "source 로 불러야 한다:  source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

_cntlp_env() {
  local repo tfvars
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  tfvars="${repo}/terraform/onp/terraform.tfvars"

  if [[ ! -f "$tfvars" ]]; then
    echo "terraform.tfvars 가 없다: $tfvars" >&2
    echo "  cp terraform/onp/terraform.tfvars.example terraform/onp/terraform.tfvars" >&2
    return 1
  fi

  local endpoint token
  endpoint="$(sed -nE 's/^[[:space:]]*proxmox_endpoint[[:space:]]*=[[:space:]]*"(.*)".*/\1/p' "$tfvars" | head -1)"
  token="$(sed -nE 's/^[[:space:]]*proxmox_api_token[[:space:]]*=[[:space:]]*"(.*)".*/\1/p' "$tfvars" | head -1)"

  if [[ -z "$endpoint" || -z "$token" ]]; then
    echo "tfvars 에서 proxmox_endpoint 또는 proxmox_api_token 을 못 읽었다." >&2
    return 1
  fi

  # user@realm!tokenid=secret 을 셋으로 가른다.
  if [[ ! "$token" =~ ^([^!]+)\!([^=]+)=(.+)$ ]]; then
    echo "proxmox_api_token 형식이 아니다. user@realm!tokenid=uuid 여야 한다." >&2
    return 1
  fi

  export PROXMOX_URL="$endpoint"
  export PROXMOX_USER="${BASH_REMATCH[1]}"
  export PROXMOX_TOKEN_ID="${BASH_REMATCH[2]}"
  export PROXMOX_TOKEN_SECRET="${BASH_REMATCH[3]}"

  # ansible.cfg 는 cwd 에서만 자동으로 읽힌다. 어디서 돌려도 잡히게 고정한다.
  export ANSIBLE_CONFIG="${repo}/ansible/ansible.cfg"

  # Proxmox 자체서명 인증서 때문에 매 실행마다 urllib3 경고가 화면을 덮는다.
  # (ANSIBLE_PYTHON_WARNINGS 라는 설정은 없다. ansible 은 이 변수를 읽지 않는다)
  export PYTHONWARNINGS=ignore

  # CNTLP_SSH_KEY 를 여기서 세우지 않는 이유는 위 "하지 않는 일" 참고.

  # 토큰은 찍지 않는다. 무엇이 설정됐는지만 알린다.
  printf '환경 설정 완료 — PROXMOX_URL=%s PROXMOX_USER=%s (토큰 2개 설정됨)\n' \
    "$PROXMOX_URL" "$PROXMOX_USER"
  printf 'ANSIBLE_CONFIG=%s\n' "$ANSIBLE_CONFIG"
}

_cntlp_env
unset -f _cntlp_env
