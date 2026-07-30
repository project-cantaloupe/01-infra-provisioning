#!/usr/bin/env bash
#
# terraform.tfvars 에서 Proxmox 자격증명을 읽어 환경변수로 내보낸다.
#
# terraform provider 와 ansible 인벤토리가 같은 토큰을 쓰는데 형식이 다르다.
#   tfvars:  proxmox_api_token = "terraform@pve!provisioning=<uuid>"
#   ansible: PROXMOX_USER / PROXMOX_TOKEN_ID / PROXMOX_TOKEN_SECRET 3개로 분해
# 매번 손으로 파싱하다 빠뜨리면 인벤토리가 **에러 없이 호스트 0개**로 성공한다.
#
# 사용법 (source 로 불러야 한다. 실행하면 자식 셸에서 끝난다):
#   source scripts/cantaloupe-env.sh
#   ansible-playbook playbooks/site-workers.yaml --tags os
#
# 값은 출력하지 않는다. 토큰이 셸 히스토리와 스크롤백에 남으면 안 된다.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "source 로 불러야 한다:  source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

_cantaloupe_env() {
  local repo tfvars
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  tfvars="${repo}/terraform/onprem/terraform.tfvars"

  if [[ ! -f "$tfvars" ]]; then
    echo "terraform.tfvars 가 없다: $tfvars" >&2
    echo "  cp terraform/onprem/terraform.tfvars.example terraform/onprem/terraform.tfvars" >&2
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

  # SSH 키는 여기서 내보내지 않는다. 기본 경로(~/.ssh/cantaloupe_ed25519)는
  # inventories/onprem/group_vars/platform_onp.yml 이 이미 기본값으로 갖고 있다.
  # CANTALOUPE_SSH_KEY 는 그 기본값을 **덮으려는** 사람이 직접 쓰는 변수다.

  # 토큰은 찍지 않는다. 무엇이 설정됐는지만 알린다.
  printf '환경 설정 완료 — PROXMOX_URL=%s PROXMOX_USER=%s (토큰 2개 설정됨)\n' \
    "$PROXMOX_URL" "$PROXMOX_USER"
  printf 'ANSIBLE_CONFIG=%s\n' "$ANSIBLE_CONFIG"
}

_cantaloupe_env
unset -f _cantaloupe_env
