#!/usr/bin/env bash
set -euo pipefail

umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
stack_dir="$(cd -- "${script_dir}/.." && pwd)"

aws_profile="${AWS_PROFILE:-cntlp}"
aws_region="${AWS_REGION:-ap-northeast-2}"
control_plane_host="cntlp-aws-cp-01"
auth_key_source=""
secret_id=""

usage() {
  cat <<'EOF'
Usage: prepare-bootstrap-secret.sh [options]

Options:
  --control-plane-host <host>       Tailscale/MagicDNS Control Plane host
  --tailscale-auth-key-file <path>  Root-readable file containing one auth key
  --secret-id <name-or-arn>         Override the Terraform output Secret ARN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-host)
      control_plane_host="${2:-}"
      shift 2
      ;;
    --tailscale-auth-key-file)
      auth_key_source="${2:-}"
      shift 2
      ;;
    --secret-id)
      secret_id="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '지원하지 않는 인자입니다: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ "${control_plane_host}" =~ ^[a-z0-9.-]+$ ]] || {
  printf 'Control Plane host 형식이 올바르지 않습니다.\n' >&2
  exit 1
}

for command_name in aws terraform tailscale python3; do
  command -v "${command_name}" >/dev/null || {
    printf '필수 명령을 찾지 못했습니다: %s\n' "${command_name}" >&2
    exit 1
  }
done

if [[ -z "${secret_id}" ]]; then
  secret_id="$(
    AWS_PROFILE="${aws_profile}" terraform -chdir="${stack_dir}" output -raw bootstrap_secret_arn
  )"
fi
[[ -n "${secret_id}" && "${secret_id}" != "null" ]] || {
  printf 'bootstrap 기반을 먼저 apply해야 합니다.\n' >&2
  exit 1
}

AWS_PROFILE="${aws_profile}" aws secretsmanager describe-secret \
  --region "${aws_region}" \
  --secret-id "${secret_id}" \
  --query ARN \
  --output text >/dev/null

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/cntlp-bootstrap-secret.XXXXXX")"
auth_key_file="${work_directory}/tailscale-auth-key"
join_command_file="${work_directory}/kubeadm-join-command"
secret_value_file="${work_directory}/secret-value.json"
token_id=""
completed=false

cleanup() {
  exit_code=$?
  trap - EXIT
  rm -rf -- "${work_directory}"

  if [[ "${completed}" != true && -n "${token_id}" ]]; then
    tailscale ssh "ubuntu@${control_plane_host}" \
      "sudo kubeadm token delete '${token_id}'" >/dev/null 2>&1 || true
  fi

  exit "${exit_code}"
}
trap cleanup EXIT

if [[ -n "${auth_key_source}" ]]; then
  [[ -r "${auth_key_source}" ]] || {
    printf 'Tailscale auth key 파일을 읽을 수 없습니다.\n' >&2
    exit 1
  }
  install -m 0600 "${auth_key_source}" "${auth_key_file}"
else
  read -r -s -p '단기 ephemeral Tailscale auth key: ' tailscale_auth_key
  printf '\n'
  printf '%s' "${tailscale_auth_key}" >"${auth_key_file}"
  unset tailscale_auth_key
fi

if ! grep -Eq '^tskey-auth-' "${auth_key_file}"; then
  printf 'Tailscale auth key 형식이 올바르지 않습니다.\n' >&2
  exit 1
fi

printf 'TTL 30분 kubeadm bootstrap token 생성\n'
tailscale ssh "ubuntu@${control_plane_host}" \
  "sudo kubeadm token create --ttl=30m --description cntlp-karpenter-boot-test --print-join-command" \
  >"${join_command_file}"

token_id="$(
  python3 - "${join_command_file}" <<'PY'
import pathlib
import re
import shlex
import sys

parts = shlex.split(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
token = parts[parts.index("--token") + 1]
token_id = token.split(".", 1)[0]
if not re.fullmatch(r"[a-z0-9]{6}", token_id):
    raise SystemExit("invalid kubeadm token id")
print(token_id)
PY
)"

python3 - "${auth_key_file}" "${join_command_file}" "${secret_value_file}" <<'PY'
import datetime
import json
import pathlib
import re
import shlex
import sys

auth_key = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
parts = shlex.split(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

try:
    join_index = parts.index("join")
    endpoint = parts[join_index + 1]
    token = parts[parts.index("--token") + 1]
    ca_hash = parts[parts.index("--discovery-token-ca-cert-hash") + 1]
except (ValueError, IndexError) as error:
    raise SystemExit("kubeadm join command parse failed") from error

if not auth_key.startswith("tskey-auth-"):
    raise SystemExit("invalid Tailscale auth key")
if not re.fullmatch(r"[^\s:]+:\d{1,5}", endpoint):
    raise SystemExit("invalid Kubernetes API endpoint")
if not re.fullmatch(r"[a-z0-9]{6}\.[a-z0-9]{16}", token):
    raise SystemExit("invalid kubeadm bootstrap token")
if not re.fullmatch(r"sha256:[a-f0-9]{64}", ca_hash):
    raise SystemExit("invalid kubeadm CA hash")

# 실제 token TTL보다 5분 짧은 안전 경계를 Bootstrap 실행기가 확인한다.
expires_at = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=25)
secret = {
    "tailscale_auth_key": auth_key,
    "api_server_endpoint": endpoint,
    "token": token,
    "ca_cert_hash": ca_hash,
    "expires_at": expires_at.isoformat().replace("+00:00", "Z"),
}

output = pathlib.Path(sys.argv[3])
output.write_text(json.dumps(secret, separators=(",", ":")), encoding="utf-8")
output.chmod(0o600)
PY

printf 'Bootstrap Secret 값 등록\n'
AWS_PROFILE="${aws_profile}" aws secretsmanager put-secret-value \
  --region "${aws_region}" \
  --secret-id "${secret_id}" \
  --secret-string "file://${secret_value_file}" \
  --query VersionId \
  --output text >/dev/null

completed=true
printf 'Bootstrap Secret 준비 완료. 25분 안에 자동 가입 Boot Test를 시작하세요.\n'
