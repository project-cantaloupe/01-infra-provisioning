#!/usr/bin/env bash
#
# 조인이 실패할 조건을 먼저 걸러내고, 그다음 조인 플레이북을 돌린다.
#
# **조인 자체는 이 스크립트가 하지 않는다.** kubeadm-worker 롤이 한다.
# 이 파일은 그 앞단(입력 정리 + 사전 점검)만 맡는다.
#
# ── 하는 일 ─────────────────────────────────────────────────────
#
# 1. `kubeadm token create --print-join-command` 출력을 **통째로** 받아
#    3개 값으로 쪼갠다 (--join-command). 값을 따로 줘도 된다
# 2. 형식을 검증한다 — endpoint 는 host:port, 토큰은 `abcdef.0123456789abcdef`,
#    해시는 `sha256:` + 64자리 hex
# 3. 조인 전 점검 — Proxmox 자격증명 로드, 인벤토리가 호스트를 잡는지,
#    조인 대상 워커 특정, **워커 → 컨트롤플레인 :6443 도달성**, CP 버전 대조
# 4. `ansible-playbook --tags join` 을 돌린다
#
# ── 하지 않는 일 ────────────────────────────────────────────────
#
# - **조인.** kubeadm-worker 롤이 소유한다
# - **사후 검증.** 롤이 마지막에 노드마다 /etc/kubernetes/kubelet.conf 를
#   stat 하고 assert 한다. 여기서 `ansible -m stat | grep -c` 로 세면 워커
#   여러 대 중 **한 대만 조인돼도 통과**해서 롤보다 부정확하다.
#   실패하면 4번의 ansible-playbook 이 0 이 아닌 값으로 죽는다
# - **노드 설정.** swap·커널 모듈·sysctl 은 common, 런타임은 containerd 소유
#
# ── 왜 필요한가 ─────────────────────────────────────────────────
#
# **kubeadm join 은 실패해도 원인을 잘 안 알려준다.** 버전 불일치, 토큰 만료,
# 도달 불가가 전부 비슷한 타임아웃으로 나타난다. 미리 갈라두면 어느 쪽인지
# 즉시 안다. 특히 3번의 도달성 점검이 걸리면 조인은 **반드시** 실패한다.
#
# 그리고 join 명령을 손으로 3개로 쪼개다 보면 `sha256:` 접두사를 빼먹거나
# 토큰 끝을 자른다. 그 실수도 조인 타임아웃으로만 드러난다.
#
# 토큰은 명령줄에 두지 않는다 — 워커의 `ps` 출력에 노출된다. 환경변수로만
# ansible 에 넘기고 화면·로그에도 남기지 않는다.
#
# ── 알려진 설계 부채 ────────────────────────────────────────────
#
# 사전 점검 대부분은 ansible 로도 표현된다 — 도달성은 `wait_for`, CP 버전은
# `uri`, 형식 검증은 `assert`. 지금은 preflight 가 **이 스크립트와
# kubeadm-worker 롤 두 층**으로 나뉘어 있어서, 새 검사를 어디에 넣을지
# 매번 헷갈린다. 플레이북 pre_tasks 로 합치면 이 파일은 --join-command
# 파싱 래퍼로 줄어든다. 아직 정리하지 않았다.
#
# ── 사용법 ──────────────────────────────────────────────────────
#   # 컨트롤플레인에서: kubeadm token create --print-join-command
#   ./scripts/join-worker.sh --join-command "kubeadm join 100.82.100.58:6443 --token ab.cd --discovery-token-ca-cert-hash sha256:ef01"
#
#   # 또는 값을 따로:
#   KUBEADM_API_ENDPOINT=100.82.100.58:6443 KUBEADM_TOKEN=ab.cd \
#   KUBEADM_CA_CERT_HASH=sha256:ef01 ./scripts/join-worker.sh
#
#   ./scripts/join-worker.sh --check-only   # 사전 점검만
#   ./scripts/join-worker.sh --dry-run      # 무엇을 실행할지만 출력

set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PLAYBOOK="playbooks/site-workers.yaml"

# playbooks/site-workers.yaml 의 hosts 와 같은 값이어야 한다. 한 번만 적는다 —
# 여러 곳에 흩어지면 한쪽만 고쳤을 때 점검 대상과 실제 조인 대상이 어긋난다.
readonly WORKERS='platform_aws:platform_gcp:platform_onp:!role_control_plane'

# 클러스터 K8s 버전의 단일 출처. bootstrap-workstation.sh 도 같은 파일을 읽는다.
readonly K8S_DEFAULTS="${REPO_DIR}/ansible/roles/kubeadm-worker/defaults/main.yml"

# ansible.cfg 의 inventory·roles_path 가 상대 경로라 ansible/ 안에서 돌려야 한다.
in_ansible() { (cd "$REPO_DIR/ansible" && "$@"); }

CHECK_ONLY=0
DRY_RUN=0
JOIN_COMMAND=""

# ── 출력 ────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
  readonly C_OK=$'\033[32m' C_WARN=$'\033[33m' C_ERR=$'\033[31m'
  readonly C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_OFF=$'\033[0m'
else
  readonly C_OK='' C_WARN='' C_ERR='' C_DIM='' C_BOLD='' C_OFF=''
fi

step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '%s  ok%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s  warn%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
die()  { printf '%s  err %s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 0
}

# ── 인자 ────────────────────────────────────────────────────────

while (( $# )); do
  case "$1" in
    --join-command) JOIN_COMMAND="${2:?--join-command 에 값이 필요하다}"; shift 2 ;;
    --check-only)   CHECK_ONLY=1; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      usage ;;
    *)              die "모르는 인자: $1  (--help 를 본다)" ;;
  esac
done

# ── join 명령 파싱 ──────────────────────────────────────────────
#
# `kubeadm token create --print-join-command` 출력을 그대로 붙여넣을 수 있게 한다.
# 손으로 3개로 쪼개다 보면 sha256: 접두사를 빼먹거나 토큰 끝을 자른다.

if [[ -n "$JOIN_COMMAND" ]]; then
  step "join 명령 파싱"

  # kubeadm join <endpoint> --token <t> --discovery-token-ca-cert-hash <h>
  # 인자 순서는 고정이 아니므로 각각 찾는다.
  _endpoint="$(grep -oE 'join[[:space:]]+[^[:space:]]+' <<<"$JOIN_COMMAND" | awk '{print $2}' || true)"
  _token="$(grep -oE -- '--token[[:space:]=]+[^[:space:]]+' <<<"$JOIN_COMMAND" | sed -E 's/--token[[:space:]=]+//' || true)"
  _hash="$(grep -oE -- '--discovery-token-ca-cert-hash[[:space:]=]+[^[:space:]]+' <<<"$JOIN_COMMAND" | sed -E 's/--discovery-token-ca-cert-hash[[:space:]=]+//' || true)"

  [[ -n "$_endpoint" ]] || die "join 명령에서 엔드포인트를 못 찾았다. 'kubeadm join <host>:6443 ...' 형식이어야 한다."
  [[ -n "$_token"    ]] || die "join 명령에서 --token 을 못 찾았다."
  [[ -n "$_hash"     ]] || die "join 명령에서 --discovery-token-ca-cert-hash 를 못 찾았다."

  export KUBEADM_API_ENDPOINT="$_endpoint"
  export KUBEADM_TOKEN="$_token"
  export KUBEADM_CA_CERT_HASH="$_hash"
  unset _endpoint _token _hash
fi

KUBEADM_API_ENDPOINT="${KUBEADM_API_ENDPOINT:-}"
KUBEADM_TOKEN="${KUBEADM_TOKEN:-}"
KUBEADM_CA_CERT_HASH="${KUBEADM_CA_CERT_HASH:-}"

# ── 사전 점검 ───────────────────────────────────────────────────

step "사전 점검"

# 1. 값이 다 있는가. 없는 것을 전부 말한다 — 하나씩 알려주면 왕복이 늘어난다.
_missing=()
[[ -n "$KUBEADM_API_ENDPOINT" ]] || _missing+=("KUBEADM_API_ENDPOINT")
[[ -n "$KUBEADM_TOKEN"        ]] || _missing+=("KUBEADM_TOKEN")
[[ -n "$KUBEADM_CA_CERT_HASH" ]] || _missing+=("KUBEADM_CA_CERT_HASH")
if (( ${#_missing[@]} )); then
  die "조인 정보가 없다: ${_missing[*]}
       컨트롤플레인 노드에서 발급한다:
         kubeadm token create --print-join-command
       출력을 통째로 넘겨도 된다:
         $0 --join-command \"kubeadm join ...\""
fi

# 2. 형식이 맞는가. sha256: 접두사를 빼먹는 실수가 흔하다.
[[ "$KUBEADM_API_ENDPOINT" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]] \
  || die "엔드포인트 형식이 틀렸다: '$KUBEADM_API_ENDPOINT' (host:port 여야 한다)"
[[ "$KUBEADM_TOKEN" =~ ^[a-z0-9]{6}\.[a-z0-9]{16}$ ]] \
  || die "토큰 형식이 틀렸다. kubeadm 토큰은 'abcdef.0123456789abcdef' 형식이다."
[[ "$KUBEADM_CA_CERT_HASH" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || die "CA 해시 형식이 틀렸다. 'sha256:' 접두사와 64자리 hex 가 있어야 한다."
ok "조인 정보 3개 형식 확인"

# 3. 환경 스크립트가 있는가
[[ -f "$REPO_DIR/scripts/cntlp-env.sh" ]] \
  || die "scripts/cntlp-env.sh 가 없다."
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/cntlp-env.sh" >/dev/null \
  || die "환경 설정에 실패했다. terraform.tfvars 를 확인한다."
ok "Proxmox 자격증명 로드"

# 4. 인벤토리가 워커를 잡는가.
#    이 스택은 인벤토리가 조용히 0개를 반환하는 실패가 잦다.
_hosts="$(in_ansible ansible-inventory --list 2>/dev/null \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len((d.get("_meta",{}).get("hostvars") or {})))' 2>/dev/null || echo 0)"
(( _hosts > 0 )) || die "인벤토리가 호스트를 0개 반환했다.
       PROXMOX_* 환경변수나 python3-proxmoxer 를 확인한다."
ok "인벤토리 호스트 ${_hosts}개"

# 5. 대상 워커를 실제로 특정한다
_targets="$(in_ansible ansible "$WORKERS" --list-hosts 2>/dev/null \
  | tail -n +2 | tr -d ' ' | grep -v '^$' || true)"
[[ -n "$_targets" ]] || die "조인 대상 워커가 없다. VM 태그(platform-*, role-*)를 확인한다."
ok "조인 대상: $(tr '\n' ' ' <<<"$_targets")"

# 6. 워커에서 API 서버에 실제로 닿는가.
#    여기가 막히면 kubeadm join 은 반드시 타임아웃으로 죽는다.
step "도달성 확인 (워커 → 컨트롤플레인)"
_cp_host="${KUBEADM_API_ENDPOINT%:*}"
_cp_port="${KUBEADM_API_ENDPOINT##*:}"

_reach="$(in_ansible ansible "$WORKERS" \
  -m shell -a "timeout 8 bash -c 'cat </dev/null >/dev/tcp/${_cp_host}/${_cp_port}' && echo REACHABLE || echo BLOCKED" \
  2>/dev/null | grep -c REACHABLE || echo 0)"
(( _reach > 0 )) || die "워커에서 ${KUBEADM_API_ENDPOINT} 에 닿지 않는다.
       메시(tailscale)가 올라와 있는지, ACL 이 6443 을 막지 않는지 확인한다.
       확인:  ansible <워커> -m shell -a 'tailscale status'"
ok "워커 → ${KUBEADM_API_ENDPOINT} 도달 확인"

# 7. 버전이 맞는가.
#    kubeadm 은 컨트롤플레인보다 1 마이너 낮은 것까지만 허용한다.
#    어긋나면 조인이 거부되는데 메시지가 불친절하다.
_cp_version="$(in_ansible ansible "$WORKERS" \
  -m shell -a "timeout 10 curl -sk https://${KUBEADM_API_ENDPOINT}/version" 2>/dev/null \
  | sed -nE 's/.*"gitVersion": *"(v[0-9.]+)".*/\1/p' | head -1 || true)"
if [[ -n "$_cp_version" ]]; then
  ok "컨트롤플레인 버전 ${_cp_version}"
  _want="$(sed -nE 's/^kubernetes_patch: *"([0-9.]+)".*/\1/p' "$K8S_DEFAULTS" || true)"
  if [[ -n "$_want" && "$_cp_version" != "v${_want}" ]]; then
    warn "롤이 고정한 버전은 ${_want} 인데 컨트롤플레인은 ${_cp_version} 이다."
    warn "마이너가 다르면 조인이 거부된다. defaults/main.yml 의 kubernetes_patch 를 맞춘다."
  fi
else
  warn "컨트롤플레인 버전을 못 읽었다. 계속 진행하지만 버전 불일치면 조인이 거부된다."
fi

if (( CHECK_ONLY )); then
  step "사전 점검만 수행했다 (--check-only)"
  ok "조인 준비 완료. --check-only 를 빼고 다시 실행하면 조인한다."
  exit 0
fi

# ── 조인 ────────────────────────────────────────────────────────

step "조인 실행"

if (( DRY_RUN )); then
  printf '%s  would run: ansible-playbook %s --tags join%s\n' "$C_DIM" "$PLAYBOOK" "$C_OFF"
  printf '%s  (환경변수 KUBEADM_API_ENDPOINT / KUBEADM_TOKEN / KUBEADM_CA_CERT_HASH 전달)%s\n' "$C_DIM" "$C_OFF"
  exit 0
fi

# 토큰은 환경변수로만 넘긴다. 명령줄에 두면 워커의 ps 출력에 노출된다.
#
# 사후 검증은 여기서 하지 않는다. kubeadm-worker 롤이 마지막에
# /etc/kubernetes/kubelet.conf 를 stat 하고 assert 한다 — 노드마다 따로 보므로
# 여기서 다시 세는 것보다 정확하다. 실패하면 이 명령이 0 이 아닌 값으로 죽는다.
cd "$REPO_DIR/ansible"
ansible-playbook "$PLAYBOOK" --tags join

ok "조인 완료"

cat <<'NEXT'

다음:

  1. 컨트롤플레인에서 노드가 보이는지 확인
       kubectl get nodes -o wide

     이 시점에 NotReady 가 정상이다 — CNI 가 아직 없다.

  2. 라벨이 붙었는지 확인 (팀 협약: platform + role)
       kubectl get node <노드명> --show-labels

  3. CNI 설치 — **MTU 를 반드시 지정한다**
     tailscale0 이 1280 이고 Calico VXLAN 이 50B 를 더 쓴다.
     기본 자동감지(eth0 1500 → 1450)로 두면 메시를 건너는 큰 패킷이
     조용히 사라진다. veth_mtu 를 1230 으로 명시한다.

  4. Kyverno 예외가 비어 있으면 CNI DaemonSet 이 거부된다.
     governance/exceptions/ 를 먼저 채운다.
NEXT
