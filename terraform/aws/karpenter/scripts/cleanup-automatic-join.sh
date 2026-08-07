#!/usr/bin/env bash
set -euo pipefail

umask 077
export AWS_PAGER=""

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
stack_dir="$(cd -- "${script_dir}/.." && pwd)"

aws_profile="${AWS_PROFILE:-cntlp}"
aws_region="${AWS_REGION:-ap-northeast-2}"
control_plane_host="${CNTLP_CONTROL_PLANE_HOST:-cntlp-aws-cp-01}"
node_name="${CNTLP_BOOT_TEST_NODE_NAME:-cntlp-aws-wk-99}"

[[ "${control_plane_host}" =~ ^[a-z0-9.-]+$ ]] || {
  printf 'Control Plane host 형식이 올바르지 않습니다.\n' >&2
  exit 1
}
[[ "${node_name}" =~ ^cntlp-aws-wk-[0-9]{2}$ ]] || {
  printf 'Boot Test Node 이름 형식이 올바르지 않습니다.\n' >&2
  exit 1
}

for command_name in aws terraform tailscale python3; do
  command -v "${command_name}" >/dev/null || {
    printf '필수 명령을 찾지 못했습니다: %s\n' "${command_name}" >&2
    exit 1
  }
done

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/cntlp-automatic-join-cleanup.XXXXXX")"
secret_value_file="${work_directory}/secret-value.json"
trap 'rm -rf -- "${work_directory}"' EXIT

secret_id="$(
  AWS_PROFILE="${aws_profile}" terraform -chdir="${stack_dir}" output -raw bootstrap_secret_arn
)"

token_id=""
if [[ -n "${secret_id}" && "${secret_id}" != "null" ]] && \
  AWS_PROFILE="${aws_profile}" aws secretsmanager get-secret-value \
    --region "${aws_region}" \
    --secret-id "${secret_id}" \
    --query SecretString \
    --output text >"${secret_value_file}"; then
  token_id="$(
    python3 - "${secret_value_file}" <<'PY'
import json
import pathlib
import re
import sys

secret = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
token_id = str(secret.get("token", "")).split(".", 1)[0]
if not re.fullmatch(r"[a-z0-9]{6}", token_id):
    raise SystemExit("invalid kubeadm token id")
print(token_id)
PY
  )"
fi

printf 'Boot Test Node drain\n'
if tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl get node '${node_name}' >/dev/null 2>&1"; then
  tailscale ssh "ubuntu@${control_plane_host}" \
    "kubectl drain '${node_name}' --ignore-daemonsets --delete-emptydir-data --force --timeout=5m"
fi

printf 'Boot Test Tailscale logout\n'
tailscale ssh "ubuntu@${node_name}" "sudo tailscale logout" || true

printf 'Boot Test Node 객체 삭제\n'
tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl delete node '${node_name}' --ignore-not-found"

if [[ -n "${token_id}" ]]; then
  printf 'kubeadm bootstrap token 삭제\n'
  tailscale ssh "ubuntu@${control_plane_host}" \
    "sudo kubeadm token delete '${token_id}'" || true
fi

printf '%s\n' \
  'Cluster와 tailnet 정리 완료.' \
  '이제 enable 인자 없이 karpenter Stack을 plan·apply해 임시 AWS 자원을 삭제하세요.'
