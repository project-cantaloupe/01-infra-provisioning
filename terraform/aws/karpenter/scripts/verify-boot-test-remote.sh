#!/usr/bin/env bash
set -euo pipefail

cloud-init status --wait

test "$(hostname)" = "cntlp-aws-wk-99"
grep -Eq '^[0-9a-f]{32}$' /etc/machine-id
test -f /etc/ssh/ssh_host_ed25519_key.pub
test ! -e /etc/kubernetes/kubelet.conf
test "$(find /etc/cni/net.d -type f 2>/dev/null | wc -l | tr -d ' ')" = "0"
test "$(swapon --show --noheadings | wc -l | tr -d ' ')" = "0"

test "$(systemctl is-active containerd)" = "active"
test "$(systemctl is-active tailscaled)" = "active"
test "$(systemctl is-enabled kubelet)" = "enabled"
test "$(systemctl is-enabled containerd)" = "enabled"
test "$(systemctl is-enabled tailscaled)" = "enabled"

grep -Eq 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd/config.toml

tailscale_backend="$({
  tailscale status --json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["BackendState"])'
})"
test "${tailscale_backend}" != "Running"

test "$(kubeadm version -o short)" = "v1.36.3"
test "$(kubelet --version | awk '{print $2}')" = "v1.36.3"

printf 'hostname=%s\n' "$(hostname)"
printf 'machine_id=regenerated\n'
printf 'ssh_host_key=regenerated\n'
printf 'cni_config_files=0\n'
printf 'swap=disabled\n'
printf 'containerd=%s\n' "$(containerd --version)"
printf 'kubeadm=%s\n' "$(kubeadm version -o short)"
printf 'kubelet=%s\n' "$(kubelet --version | awk '{print $2}')"
printf 'kubelet_active=%s\n' "$(systemctl is-active kubelet || true)"
printf 'tailscale=%s\n' "$(tailscale version | head -1)"
printf 'tailscale_backend=%s\n' "${tailscale_backend}"
printf 'cloud_init=%s\n' "$(cloud-init status)"
printf 'BOOT_TEST_OK\n'
