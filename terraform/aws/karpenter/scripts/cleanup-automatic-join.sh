#!/usr/bin/env bash
set -euo pipefail

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

for command_name in tailscale ssh; do
  command -v "${command_name}" >/dev/null || {
    printf '필수 명령을 찾지 못했습니다: %s\n' "${command_name}" >&2
    exit 1
  }
done

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/cntlp-automatic-join-cleanup.XXXXXX")"
trap 'rm -rf -- "${work_directory}"' EXIT

node_ip="$(
  tailscale ssh "ubuntu@${control_plane_host}" \
    "kubectl get node '${node_name}' -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'" \
    2>/dev/null || true
)"
if [[ -n "${node_ip}" && ! "${node_ip}" =~ ^100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  printf 'Boot Test Node의 Tailscale InternalIP 형식이 올바르지 않습니다.\n' >&2
  node_ip=""
fi

printf 'Boot Test Node drain\n'
if tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl get node '${node_name}' >/dev/null 2>&1"; then
  tailscale ssh "ubuntu@${control_plane_host}" \
    "kubectl drain '${node_name}' --ignore-daemonsets --delete-emptydir-data --force --timeout=5m"
fi

printf 'Boot Test Tailscale logout\n'
if [[ -n "${node_ip}" ]]; then
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=15 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="${work_directory}/known_hosts" \
    "ubuntu@${node_ip}" \
    "sudo tailscale logout" || true
else
  printf 'Boot Test Node InternalIP를 찾지 못해 Tailscale logout을 건너뜁니다.\n' >&2
fi

printf 'Boot Test Node 객체 삭제\n'
tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl delete node '${node_name}' --ignore-not-found"

printf '%s\n' \
  'Cluster와 tailnet 정리 완료.' \
  '회전 중인 kubeadm token은 다른 신규 Worker가 사용할 수 있으므로 유지합니다.' \
  '이제 enable_boot_test 없이 karpenter Stack을 plan·apply해 임시 EC2를 삭제하세요.'
