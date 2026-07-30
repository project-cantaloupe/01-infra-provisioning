#!/usr/bin/env bash
#
# 워크스테이션에 terraform · ansible · kubectl · aws · vault 를 깐다.
#
# 여기서 "워크스테이션"은 사람이 명령을 치는 PC 다.
# Proxmox 호스트도 워커 VM 도 아니다 —
#   - Proxmox 호스트: terraform 이 API·SSH 로 조종하는 대상이다. 아무것도 안 깐다
#   - 워커 VM: containerd·kubelet 은 ansible 롤이 넣는다. 손으로 안 깐다
#
# 대상: Debian 계열 (Ubuntu 24.04 noble 에서 확인)
# 이미 깔린 것은 건너뛴다. 여러 번 돌려도 안전하다.
#
# 사용법:
#   ./scripts/bootstrap-workstation.sh
#   ./scripts/bootstrap-workstation.sh --k8s-minor v1.33
#   ./scripts/bootstrap-workstation.sh --dry-run
#   ./scripts/bootstrap-workstation.sh --skip-kubectl
#   ./scripts/bootstrap-workstation.sh --skip-aws --skip-vault
#   ./scripts/bootstrap-workstation.sh --skip-cloud-inventory

set -euo pipefail

# ── 설정 ────────────────────────────────────────────────────────

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# terraform/aws/*/versions.tf 가 ">= 1.11.0, < 2.0.0" 을 요구한다.
# 하한을 낮게 두면 1.10 이 "충족" 으로 통과하고, 그 뒤 terraform init 이
# AWS 스택에서 거부한다 — 설치 단계에서 걸러야 할 것을 apply 직전에 만난다.
# (1.10 은 backend 의 use_lockfile 하한이었다. onp·gcp 는 아직 그 값이지만
#  워크스테이션은 가장 높은 요구치를 만족해야 한다)
readonly TERRAFORM_MIN_VERSION="1.11.0"

# 클러스터 K8s 버전의 단일 출처는 ansible 롤이다. 여기 다시 적지 않는다 —
# 워커의 kubelet 과 이 PC 의 kubectl 이 다른 마이너면 kubectl 이 클러스터에
# 안 붙는다. 두 곳에 적어두면 한쪽만 올리게 된다.
# 덮어쓰려면 --k8s-minor 를 쓴다.
# 출처는 ansible/vars/cluster.yml 의 kubernetes_minor_version 이다.
# 한때 kubeadm-worker/defaults/main.yml 의 kubernetes_minor 였고, 클러스터 구성이
# 합쳐질 때 옮겨졌는데 이 스크립트는 옛 경로를 계속 읽어 **빈 값**을 받고 있었다.
# install_kubectl 의 가드가 die 로 잡아주므로 조용히 깨지지는 않았지만,
# 에러 메시지가 "--k8s-minor 를 직접 줘라" 로 나와서 진짜 원인(경로가 옮겨졌다)을
# 가린다. SKIP_KUBECTL=1 이 기본이라 아직 아무도 만나지 않았다.
readonly K8S_DEFAULTS="${REPO_DIR}/ansible/vars/cluster.yml"
K8S_MINOR="$(sed -nE 's/^kubernetes_minor_version: *"?([^"[:space:]]+)"?.*/\1/p' "$K8S_DEFAULTS" 2>/dev/null || true)"

SKIP_TERRAFORM=0
SKIP_ANSIBLE=0
SKIP_KUBECTL=1
SKIP_AWS=0
SKIP_VAULT=0
# AWS 스택(terraform/aws/*)과 동적 인벤토리(inventories/aws/aws_ec2.yaml)가
# 실재하므로 기본으로 켠다. 이게 없으면 인벤토리가 amazon.aws 플러그인을 못 찾고,
# ansible.cfg 의 unparsed_is_failed 가 그걸 에러로 만든다.
WITH_CLOUD_INVENTORY=1
DRY_RUN=0

# ── 출력 ────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
  readonly C_OK=$'\033[32m' C_WARN=$'\033[33m' C_ERR=$'\033[31m'
  readonly C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_OFF=$'\033[0m'
else
  readonly C_OK='' C_WARN='' C_ERR='' C_DIM='' C_BOLD='' C_OFF=''
fi

step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '%s  ok%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
skip() { printf '%s  skip %s%s\n' "$C_DIM" "$*" "$C_OFF"; }
warn() { printf '%s  warn%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
die()  { printf '%s  err %s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

# --dry-run 이면 찍기만 한다.
run() {
  if (( DRY_RUN )); then
    printf '%s  would run: %s%s\n' "$C_DIM" "$*" "$C_OFF"
  else
    "$@"
  fi
}

# `cmd | head -1` 을 쓰지 않는다. head 가 먼저 파이프를 닫으면 앞 명령이 SIGPIPE 로
# 죽고, set -o pipefail 이 그걸 실패(141)로 잡아 스크립트가 통째로 멈춘다.
# 전부 받아서 첫 줄만 잘라낸다.
first_line() {
  local out
  out="$("$@" 2>/dev/null)" || true
  printf '%s' "${out%%$'\n'*}"
}

# GPG 키를 받아 keyring 으로 만든다.
#
# `curl ... | sudo gpg --dearmor -o dest` 를 bash -c 안에서 돌리지 않는다.
# 안쪽 셸에는 pipefail 이 없어서 curl 의 404·403 이 gpg 의 성공에 가려지고,
# 빈 입력을 받은 gpg 가 목적지에 0바이트 파일을 남긴다. 그 파일이 다음 실행 때
# "이미 있음" 으로 통과하면 apt-get update 에서야 터진다.
install_keyring() {
  local url="$1" dest="$2" label="$3"

  # -f 가 아니라 -s 로 본다. 0바이트 keyring 은 있는 게 아니라 깨진 것이다.
  if [[ -s "$dest" ]]; then
    skip "${label} GPG 키가 이미 있다"
    return 0
  fi
  [[ -e "$dest" ]] && { warn "0바이트 ${label} keyring 을 발견했다. 다시 받는다."; run sudo rm -f "$dest"; }

  if (( DRY_RUN )); then
    printf '%s  would run: curl -fsSL %s | gpg --dearmor > %s%s\n' "$C_DIM" "$url" "$dest" "$C_OFF"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  curl -fsSL "$url" -o "$tmp" || die "${label} GPG 키를 받지 못했다: ${url}"
  [[ -s "$tmp" ]] || die "${label} GPG 키가 비어 있다: ${url}"

  sudo gpg --batch --yes --dearmor -o "$dest" "$tmp" || die "${label} GPG 키 변환 실패"
  sudo chmod 644 "$dest"
  ok "${label} GPG 키 등록"
}

usage() {
  # 셔뱅 다음 주석 블록을 그대로 쓴다. 주석이 아닌 줄을 만나면 멈춘다.
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 0
}

# ── 인자 ────────────────────────────────────────────────────────

while (( $# )); do
  case "$1" in
    --k8s-minor)          K8S_MINOR="${2:?--k8s-minor 에 값이 필요하다 (예: v1.34)}"; shift 2 ;;
    --skip-terraform)     SKIP_TERRAFORM=1; shift ;;
    --skip-ansible)       SKIP_ANSIBLE=1; shift ;;
    --skip-kubectl)       SKIP_KUBECTL=1; shift ;;
    --skip-aws)           SKIP_AWS=1; shift ;;
    --skip-vault)         SKIP_VAULT=1; shift ;;
    --with-cloud-inventory) WITH_CLOUD_INVENTORY=1; shift ;;
    --skip-cloud-inventory) WITH_CLOUD_INVENTORY=0; shift ;;
    --dry-run)            DRY_RUN=1; shift ;;
    -h|--help)            usage ;;
    *)                    die "모르는 인자: $1  (--help 를 본다)" ;;
  esac
done

# ── 사전 점검 ───────────────────────────────────────────────────

if (( DRY_RUN )); then
  printf '\n%s[DRY RUN] 실제로 설치하지 않는다. 무엇을 실행할지만 보여준다.%s\n' "$C_WARN" "$C_OFF"
fi

step "환경 확인"

command -v apt-get >/dev/null || die "apt-get 이 없다. 이 스크립트는 Debian 계열 전용이다."

# Proxmox 호스트에서 돌리는 것을 막는다.
# 호스트를 다시 세울 때 쓸 도구가 그 호스트와 함께 죽으면 곤란하다.
# tfstate 를 S3 에 두는 것과 같은 이유다 (README 참고).
if command -v pveversion >/dev/null 2>&1; then
  die "Proxmox 호스트에서 실행하고 있다. 이 스크립트는 워크스테이션용이다.
       Proxmox 호스트에는 아무것도 설치하지 않는다 — 필요한 것은 설정뿐이다
       (snippets 콘텐츠 타입, API 토큰, root SSH).
       terraform/onp/README.md 를 본다."
fi

# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null || die "/etc/os-release 를 읽을 수 없다."
readonly DISTRO_ID="${ID:-unknown}"
readonly DISTRO_CODENAME="${VERSION_CODENAME:-unknown}"
readonly ARCH="$(dpkg --print-architecture)"

ok "${PRETTY_NAME:-$DISTRO_ID} / ${ARCH}"

if [[ "$DISTRO_CODENAME" != "noble" ]]; then
  warn "noble 이 아닌 ${DISTRO_CODENAME} 이다. 저장소 URL 이 코드네임을 그대로 쓰므로
       해당 배포판용 패키지가 없으면 apt-get update 에서 실패한다."
fi

if grep -qi microsoft /proc/version 2>/dev/null; then
  ok "WSL2 감지. 여기서 도구를 돌리고 Proxmox·VM 에는 네트워크로 붙는다."
fi

# sudo 는 사람이 비밀번호를 넣어야 할 수 있다. 먼저 한 번 받아둔다.
if (( ! DRY_RUN )); then
  step "sudo 확인"
  if sudo -n true 2>/dev/null; then
    ok "비밀번호 없이 sudo 가능"
  else
    warn "sudo 비밀번호가 필요하다. 지금 입력한다."
    sudo -v || die "sudo 를 얻지 못했다."
  fi
fi

APT_UPDATED=0
apt_update_once() {
  (( APT_UPDATED )) && return 0
  run sudo apt-get update -qq
  APT_UPDATED=1
}

apt_install() {
  apt_update_once
  run sudo apt-get install -y -qq "$@"
}

# ── terraform ───────────────────────────────────────────────────

install_terraform() {
  step "terraform"

  if command -v terraform >/dev/null 2>&1; then
    local current
    current="$(first_line terraform version)"
    current="${current#Terraform v}"

    # 설치돼 있어도 하한 미만이면 AWS 스택이 init 을 거부한다.
    # first_line 을 쓰는 이유는 위 주석과 같다 — head 를 파이프로 붙이지 않는다.
    if [[ "$(first_line sort -V <<< "$TERRAFORM_MIN_VERSION"$'\n'"$current")" \
          == "$TERRAFORM_MIN_VERSION" ]]; then
      skip "이미 설치됨 — v${current} (>= ${TERRAFORM_MIN_VERSION})"
      return 0
    fi
    warn "v${current} 은 ${TERRAFORM_MIN_VERSION} 미만이다. terraform/aws/* 가 init 을 거부한다. 업그레이드한다."
  fi

  ensure_hashicorp_repo

  apt_install terraform
  ok "terraform 설치 완료"
}

# terraform 과 vault 가 같은 apt 저장소에서 온다. 등록을 두 곳에 복사해두면
# 한쪽만 고치게 되므로 함수로 뽑는다. 두 단계 모두 멱등이라 여러 번 불러도 된다.
ensure_hashicorp_repo() {
  apt_install gnupg software-properties-common curl

  local keyring=/usr/share/keyrings/hashicorp-archive-keyring.gpg
  install_keyring "https://apt.releases.hashicorp.com/gpg" "$keyring" "HashiCorp"

  local list=/etc/apt/sources.list.d/hashicorp.list
  if [[ -f "$list" ]]; then
    skip "HashiCorp 저장소가 이미 있다"
  else
    run bash -c "echo 'deb [signed-by=${keyring}] \
https://apt.releases.hashicorp.com ${DISTRO_CODENAME} main' | sudo tee '$list' > /dev/null"
    APT_UPDATED=0   # 저장소가 늘었으니 다시 받는다
    ok "저장소 등록"
  fi
}

# ── ansible ─────────────────────────────────────────────────────

install_ansible() {
  step "ansible"

  if command -v ansible >/dev/null 2>&1; then
    skip "이미 설치됨 — $(first_line ansible --version)"
  else
    # ansible-core 가 아니라 ansible 을 깐다. 컬렉션이 같이 온다.
    apt_install ansible
    ok "ansible 설치 완료"
  fi

  # Proxmox 동적 인벤토리(ansible/inventories/onp/proxmox.yaml)의 의존성.
  #
  # pip3 install --user 를 쓰지 않는다. Ubuntu 24.04 는 PEP 668
  # (EXTERNALLY-MANAGED) 이라 시스템 파이썬에 pip 로 넣는 것이 막혀 있다.
  # apt 패키지가 있으므로 그쪽을 쓴다.
  step "ansible — Proxmox 인벤토리 의존성"
  if python3 -c 'import proxmoxer' 2>/dev/null; then
    skip "proxmoxer 이미 있음"
  else
    apt_install python3-proxmoxer python3-requests
    ok "proxmoxer 설치 완료"
  fi

  # 이게 빠지면 인벤토리가 에러 없이 호스트 0개로 성공한다.
  # 2단계의 keyed_groups 누락과 증상이 같아서 원인을 헷갈리기 쉽다.
  if (( ! DRY_RUN )) && ! python3 -c 'import proxmoxer' 2>/dev/null; then
    warn "proxmoxer 를 import 하지 못한다. 인벤토리가 호스트 0개로 조용히 성공할 것이다."
  fi

  step "ansible — 컬렉션"
  if (( DRY_RUN )); then
    printf '%s  would run: ansible-galaxy collection install community.general%s\n' "$C_DIM" "$C_OFF"
  elif [[ "$(ansible-galaxy collection list community.general 2>/dev/null)" == *community.general* ]]; then
    skip "community.general 이미 있음 (apt 의 ansible 패키지에 포함)"
  else
    ansible-galaxy collection install community.general
    ok "community.general 설치 완료"
  fi

  if (( WITH_CLOUD_INVENTORY )); then
    step "ansible — AWS·GCP 인벤토리 의존성"
    apt_install python3-boto3 python3-requests-oauthlib
    if (( DRY_RUN )); then
      printf '%s  would run: ansible-galaxy collection install amazon.aws google.cloud%s\n' "$C_DIM" "$C_OFF"
    else
      ansible-galaxy collection install amazon.aws google.cloud
    fi
    ok "클라우드 인벤토리 의존성 설치 완료"
  fi
}

# ── aws CLI ─────────────────────────────────────────────────────
#
# apt 의 awscli 를 쓰지 않는다. Ubuntu 24.04 의 것은 v1 이고 SSO 로그인과
# ec2-instance-connect open-tunnel 서브커맨드가 없다. 공식 zip 이 v2 다.
#
# **EICE 터널이 이것 없이는 안 된다.** ansible/inventories/aws/group_vars/all.yml
# 의 ansible_ssh_common_args 가 ProxyCommand 로 `aws ec2-instance-connect
# open-tunnel` 을 부른다. 즉 aws CLI 가 AWS 노드로 가는 SSH 경로 자체다.
#
# 그리고 자격증명을 가른다. terraform 은 자격증명이 없거나 만료됐거나 권한이
# 없을 때 전부 "no valid credential sources" 하나로 죽는데,
# `aws sts get-caller-identity` 가 그 셋을 갈라준다.

install_aws_cli() {
  step "aws CLI"

  if command -v aws >/dev/null 2>&1; then
    local current
    current="$(first_line aws --version)"
    # v1 이 깔려 있으면 건너뛰지 않는다. EICE 터널이 v2 전용이다.
    if [[ "$current" == aws-cli/2.* ]]; then
      skip "이미 설치됨 — ${current}"
      return 0
    fi
    warn "${current} 는 v1 이다. EICE 터널(ec2-instance-connect open-tunnel)이 없다. v2 로 올린다."
  fi

  local arch
  case "$ARCH" in
    amd64) arch=x86_64 ;;
    arm64) arch=aarch64 ;;
    *)     die "aws CLI 를 지원하지 않는 아키텍처: ${ARCH}" ;;
  esac

  local url="https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip"

  if (( DRY_RUN )); then
    printf '%s  would run: curl -fsSL %s | unzip && sudo ./aws/install --update%s\n' "$C_DIM" "$url" "$C_OFF"
    return 0
  fi

  apt_install unzip curl

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  curl -fsSL "$url" -o "$tmp/awscliv2.zip" || die "aws CLI 를 받지 못했다: ${url}"
  [[ -s "$tmp/awscliv2.zip" ]] || die "받은 aws CLI zip 이 비어 있다: ${url}"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp" || die "aws CLI 압축을 풀지 못했다"
  sudo "$tmp/aws/install" --update >/dev/null || die "aws CLI 설치 실패"

  ok "aws CLI 설치 완료 — $(first_line aws --version)"
}

# ── vault CLI ───────────────────────────────────────────────────
#
# terraform 과 같은 HashiCorp 저장소에서 온다.
#
# 서버가 아니라 클라이언트로 쓴다. 패키지에 서비스가 같이 오지만 시작하지
# 않는다 — Vault 서버는 EC2 에 ansible vault-server 롤이 올린다.
#
# 워크스테이션에 있어야 하는 이유는 두 가지다.
#   1. scripts/cntlp-env.sh 가 SSH 개인키를 Vault 에서 당겨 ssh-agent 에 넣는다
#   2. secret_id 발급과 시크릿 투입은 사람이 CLI 로 한다 — terraform 이 하면
#      그 값이 tfstate 에 평문으로 남는다 (tasks/doing/006_vault-setup.md 6절)

install_vault_cli() {
  step "vault CLI"

  if command -v vault >/dev/null 2>&1; then
    skip "이미 설치됨 — $(first_line vault version)"
    return 0
  fi

  ensure_hashicorp_repo

  apt_install vault
  ok "vault CLI 설치 완료 — $(first_line vault version)"
}

# ── kubectl ─────────────────────────────────────────────────────

install_kubectl() {
  # pkgs.k8s.io 의 경로는 **마이너까지만** 받는다 (패치를 넣으면 403).
  # 이유와 예시는 단일 출처에 적혀 있다 — $K8S_DEFAULTS 의 kubernetes_minor_version.
  # 여기서 안 막으면 apt-get update 에서야 터진다.
  if [[ ! "$K8S_MINOR" =~ ^v[0-9]+\.[0-9]+$ ]]; then
    if [[ "$K8S_MINOR" =~ ^v?([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
      local fixed="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
      warn "K8S_MINOR='${K8S_MINOR}' 는 저장소 경로로 못 쓴다. '${fixed}' 로 고쳐서 진행한다."
      K8S_MINOR="$fixed"
    else
      die "K8s 마이너 버전을 정하지 못했다: '${K8S_MINOR}'
       ${K8S_DEFAULTS} 의 kubernetes_minor_version 을 읽지 못했을 수 있다.
       --k8s-minor v1.36 처럼 직접 줄 수도 있다."
    fi
  fi

  step "kubectl (${K8S_MINOR})"

  if command -v kubectl >/dev/null 2>&1; then
    skip "이미 설치됨 — $(first_line kubectl version --client)"
    return 0
  fi

  apt_install apt-transport-https ca-certificates curl gnupg

  run sudo mkdir -p -m 755 /etc/apt/keyrings

  local keyring=/etc/apt/keyrings/kubernetes-apt-keyring.gpg
  install_keyring \
    "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
    "$keyring" "Kubernetes"

  # 저장소 URL 에 마이너 버전이 박혀 있다. 마이너를 바꾸려면 이 줄을 다시 써야 한다.
  local list=/etc/apt/sources.list.d/kubernetes.list
  if [[ -f "$list" ]] && grep -q "stable:/${K8S_MINOR}/deb" "$list"; then
    skip "Kubernetes 저장소가 이미 ${K8S_MINOR} 로 설정돼 있다"
  else
    run bash -c "echo 'deb [signed-by=${keyring}] \
https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /' | sudo tee '$list' > /dev/null"
    run sudo chmod 644 "$list"
    APT_UPDATED=0
    ok "저장소 등록 (${K8S_MINOR})"
  fi

  apt_install kubectl
  ok "kubectl 설치 완료"
}

# ── 실행 ────────────────────────────────────────────────────────

(( SKIP_TERRAFORM )) || install_terraform
(( SKIP_ANSIBLE ))   || install_ansible
(( SKIP_KUBECTL ))   || install_kubectl
(( SKIP_AWS ))       || install_aws_cli
(( SKIP_VAULT ))     || install_vault_cli

# ── 요약 ────────────────────────────────────────────────────────

step "결과"

check() {
  local name="$1" ver
  if command -v "$name" >/dev/null 2>&1; then
    case "$name" in
      terraform) ver="$(first_line terraform version)" ;;
      ansible)   ver="$(first_line ansible --version)" ;;
      kubectl)   ver="$(first_line kubectl version --client)" ;;
      aws)       ver="$(first_line aws --version)" ;;
      vault)     ver="$(first_line vault version)" ;;
    esac
    printf '%s  ok%s   %-10s %s\n' "$C_OK" "$C_OFF" "$name" "$ver"
  else
    printf '%s  없음%s %-10s\n' "$C_ERR" "$C_OFF" "$name"
  fi
}

check terraform
check ansible
check kubectl
check aws
check vault

cat <<'NEXT'

다음:

  1. terraform 코드 확인 (버킷·자격증명 없이 가능)
       cd terraform/onp
       terraform init -backend=false && terraform validate

  2. Proxmox 준비 — 토큰 발급, 스토리지에 Snippets 콘텐츠 타입 켜기
       terraform/onp/README.md

  3. VM 생성
       cp terraform.tfvars.example terraform.tfvars   # 채운다
       terraform init && terraform plan && terraform apply

  4. 인벤토리가 VM 을 잡는지 확인 — 여기서 자주 끊긴다
       ansible-inventory -i ansible/inventories/onp/proxmox.yaml --graph

kubectl 은 AWS 컨트롤플레인이 서고 이 PC 가 메시에 들어가야 쓸 수 있다.
NEXT
