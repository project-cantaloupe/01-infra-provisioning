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

command -v tailscale >/dev/null || {
  printf 'tailscale CLI가 필요합니다.\n' >&2
  exit 1
}
command -v python3 >/dev/null || {
  printf 'python3가 필요합니다.\n' >&2
  exit 1
}
command -v ssh >/dev/null || {
  printf 'ssh CLI가 필요합니다.\n' >&2
  exit 1
}

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/cntlp-automatic-join.XXXXXX")"
node_file="${work_directory}/node.json"
pod_file="${work_directory}/pods.json"
verification_file="${work_directory}/verification.txt"
verification_error_file="${work_directory}/verification-error.txt"
trap 'rm -rf -- "${work_directory}"' EXIT

node_seen=false
for attempt in $(seq 1 24); do
  if tailscale ssh "ubuntu@${control_plane_host}" \
    "kubectl get node '${node_name}' -o json" >"${node_file}" 2>/dev/null; then
    node_seen=true
    break
  fi
  sleep 5
done

if [[ "${node_seen}" != true ]]; then
  printf 'AUTOMATIC_JOIN_FAILED node=%s checks=node-registration\n' "${node_name}" >&2
  exit 1
fi

tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl wait --for=condition=Ready node/'${node_name}' --timeout=5m" >/dev/null

verification_succeeded=false
for attempt in $(seq 1 60); do
  tailscale ssh "ubuntu@${control_plane_host}" \
    "kubectl get node '${node_name}' -o json" >"${node_file}"
  tailscale ssh "ubuntu@${control_plane_host}" \
    "kubectl get pods -A --field-selector spec.nodeName='${node_name}' -o json" >"${pod_file}"

  if python3 - "${node_file}" "${pod_file}" \
    >"${verification_file}" 2>"${verification_error_file}" <<'PY'
import json
import pathlib
import sys

node = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
pods = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))

name = node["metadata"]["name"]
labels = node["metadata"].get("labels", {})
provider_id = node["spec"].get("providerID", "")
ready = next(
    (
        condition.get("status")
        for condition in node["status"].get("conditions", [])
        if condition.get("type") == "Ready"
    ),
    "",
)
internal_ip = next(
    (
        address.get("address", "")
        for address in node["status"].get("addresses", [])
        if address.get("type") == "InternalIP"
    ),
    "",
)

checks = {
    "ready": ready == "True",
    "platform": labels.get("platform") == "aws",
    "role": labels.get("role") == "service",
    "provider_id": provider_id.startswith("aws:///ap-northeast-2"),
    "tailscale_internal_ip": internal_ip.startswith("100."),
}

ready_pods = {
    (item["metadata"]["namespace"], item["metadata"]["name"])
    for item in pods.get("items", [])
    if any(
        condition.get("type") == "Ready" and condition.get("status") == "True"
        for condition in item.get("status", {}).get("conditions", [])
    )
}
required_prefixes = {
    "calico-node": ("calico-system", "calico-node-"),
    "kube-proxy": ("kube-system", "kube-proxy-"),
    "istio-cni": ("istio-cni", "istio-cni-node-"),
    "ztunnel": ("ztunnel", "ztunnel-"),
    "ebs-csi-node": ("storage-system", "ebs-csi-node-"),
}
for label, (namespace, prefix) in required_prefixes.items():
    checks[label] = any(
        pod_namespace == namespace and pod_name.startswith(prefix)
        for pod_namespace, pod_name in ready_pods
    )

failed = [label for label, passed in checks.items() if not passed]
if failed:
    raise SystemExit(f"AUTOMATIC_JOIN_FAILED node={name} checks={','.join(failed)}")

print(f"node={name}")
print(f"ready={ready}")
print(f"internal_ip={internal_ip}")
print(f"provider_id={provider_id}")
print("daemonsets=ready")
print("AUTOMATIC_JOIN_OK")
PY
  then
    verification_succeeded=true
    break
  fi

  sleep 5
done

if [[ "${verification_succeeded}" != true ]]; then
  cat "${verification_error_file}" >&2
  exit 1
fi

cat "${verification_file}"

node_ip="$(python3 - "${node_file}" <<'PY'
import json
import pathlib
import sys

node = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(
    next(
        address["address"]
        for address in node["status"].get("addresses", [])
        if address.get("type") == "InternalIP"
    )
)
PY
)"
[[ "${node_ip}" =~ ^100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || {
  printf 'AUTOMATIC_JOIN_FAILED node=%s checks=tailscale-internal-ip\n' "${node_name}" >&2
  exit 1
}

# 동일한 MagicDNS 이름을 반복 가입한 검증에서 tailscale ssh wrapper가 대기한 사례가
# 있었다. Kubernetes가 확인한 현재 Tailscale InternalIP로 직접 접속하고 테스트 전용
# known_hosts는 임시 디렉터리와 함께 제거한다.
ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=15 \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="${work_directory}/known_hosts" \
  "ubuntu@${node_ip}" \
  "sudo test -s /var/lib/cntlp/bootstrap-complete && sudo cat /var/lib/cntlp/bootstrap-complete"
