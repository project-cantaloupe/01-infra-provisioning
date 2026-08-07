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

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/cntlp-automatic-join.XXXXXX")"
node_file="${work_directory}/node.json"
pod_file="${work_directory}/pods.json"
trap 'rm -rf -- "${work_directory}"' EXIT

tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl get node '${node_name}' -o json" >"${node_file}"
tailscale ssh "ubuntu@${control_plane_host}" \
  "kubectl get pods -A --field-selector spec.nodeName='${node_name}' -o json" >"${pod_file}"

python3 - "${node_file}" "${pod_file}" <<'PY'
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

running_pods = {
    (item["metadata"]["namespace"], item["metadata"]["name"])
    for item in pods.get("items", [])
    if item.get("status", {}).get("phase") == "Running"
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
        for pod_namespace, pod_name in running_pods
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

tailscale ssh "ubuntu@${node_name}" \
  "sudo test -s /var/lib/cntlp/bootstrap-complete && sudo cat /var/lib/cntlp/bootstrap-complete"
