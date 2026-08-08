#!/usr/bin/env bash
set -euo pipefail

umask 077
export AWS_PAGER=""

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
stack_dir="$(cd -- "${script_dir}/.." && pwd)"

aws_profile="${AWS_PROFILE:-cntlp}"
aws_region="${AWS_REGION:-ap-northeast-2}"
control_plane_host="cntlp-aws-cp-01"
client_secret_source=""
tailscale_oauth_secret_id=""
kubeadm_join_secret_id=""

usage() {
  cat <<'EOF'
Usage: prepare-bootstrap-secret.sh [options]

Options:
  --control-plane-host <host>            Tailscale/MagicDNS Control Plane host
  --tailscale-client-secret-file <path>  Root-readable file containing one OAuth client secret
  --tailscale-oauth-secret-id <id>       Override the Terraform output Tailscale Secret ARN
  --kubeadm-join-secret-id <id>          Override the Terraform output kubeadm Secret ARN
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --control-plane-host)
      control_plane_host="${2:-}"
      shift 2
      ;;
    --tailscale-client-secret-file)
      client_secret_source="${2:-}"
      shift 2
      ;;
    --tailscale-oauth-secret-id)
      tailscale_oauth_secret_id="${2:-}"
      shift 2
      ;;
    --kubeadm-join-secret-id)
      kubeadm_join_secret_id="${2:-}"
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

if [[ -z "${tailscale_oauth_secret_id}" ]]; then
  tailscale_oauth_secret_id="$(
    AWS_PROFILE="${aws_profile}" terraform -chdir="${stack_dir}" \
      output -raw tailscale_oauth_secret_arn
  )"
fi
if [[ -z "${kubeadm_join_secret_id}" ]]; then
  kubeadm_join_secret_id="$(
    AWS_PROFILE="${aws_profile}" terraform -chdir="${stack_dir}" \
      output -raw kubeadm_join_secret_arn
  )"
fi

for secret_id in "${tailscale_oauth_secret_id}" "${kubeadm_join_secret_id}"; do
  [[ -n "${secret_id}" && "${secret_id}" != "null" ]] || {
    printf 'Bootstrap 기반을 먼저 apply해야 합니다.\n' >&2
    exit 1
  }
  AWS_PROFILE="${aws_profile}" aws secretsmanager describe-secret \
    --region "${aws_region}" \
    --secret-id "${secret_id}" \
    --query ARN \
    --output text >/dev/null
done

printf 'Control Plane의 kubeadm token 회전 서비스 확인\n'
tailscale ssh "ubuntu@${control_plane_host}" \
  "sudo systemctl cat cntlp-kubeadm-token-rotate.service >/dev/null && sudo systemctl is-enabled cntlp-kubeadm-token-rotate.timer >/dev/null"

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/cntlp-bootstrap-secret.XXXXXX")"
client_secret_file="${work_directory}/tailscale-client-secret"
secret_value_file="${work_directory}/tailscale-oauth-secret.json"
trap 'rm -rf -- "${work_directory}"' EXIT

if [[ -n "${client_secret_source}" ]]; then
  [[ -r "${client_secret_source}" ]] || {
    printf 'Tailscale OAuth client secret 파일을 읽을 수 없습니다.\n' >&2
    exit 1
  }
  install -m 0600 "${client_secret_source}" "${client_secret_file}"
else
  read -r -s -p 'tag:cntlp-wk 제한 Tailscale OAuth client secret: ' tailscale_client_secret
  printf '\n'
  printf '%s' "${tailscale_client_secret}" >"${client_secret_file}"
  unset tailscale_client_secret
fi

if ! grep -Eq '^tskey-client-' "${client_secret_file}"; then
  printf 'Tailscale OAuth client secret 형식이 올바르지 않습니다.\n' >&2
  exit 1
fi

python3 - "${client_secret_file}" "${secret_value_file}" <<'PY'
import json
import pathlib
import sys

client_secret = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if not client_secret.startswith("tskey-client-"):
    raise SystemExit("invalid Tailscale OAuth client secret")

output = pathlib.Path(sys.argv[2])
output.write_text(
    json.dumps({"oauth_client_secret": client_secret}, separators=(",", ":")),
    encoding="utf-8",
)
output.chmod(0o600)
PY

printf 'Tailscale OAuth Secret 값 등록\n'
AWS_PROFILE="${aws_profile}" aws secretsmanager put-secret-value \
  --region "${aws_region}" \
  --secret-id "${tailscale_oauth_secret_id}" \
  --secret-string "file://${secret_value_file}" \
  --query VersionId \
  --output text >/dev/null

rm -f -- "${client_secret_file}" "${secret_value_file}"

printf 'Control Plane에서 kubeadm token 즉시 회전\n'
tailscale ssh "ubuntu@${control_plane_host}" \
  "sudo systemctl start cntlp-kubeadm-token-rotate.service && sudo systemctl start cntlp-kubeadm-token-rotate.timer"

AWS_PROFILE="${aws_profile}" aws secretsmanager get-secret-value \
  --region "${aws_region}" \
  --secret-id "${kubeadm_join_secret_id}" \
  --query VersionId \
  --output text >/dev/null

printf '%s\n' \
  'Bootstrap Secret 준비 완료.' \
  'Tailscale OAuth 자격 증명은 Worker 가입 시 사용되고 kubeadm token은 Control Plane 타이머가 12시간마다 회전합니다.'
