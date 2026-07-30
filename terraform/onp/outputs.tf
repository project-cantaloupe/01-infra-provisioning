output "worker_names" {
  description = "VM 이름. 그대로 K8s 노드 이름이 된다."
  value       = local.worker_names
}

output "worker_vm_ids" {
  description = "Proxmox VMID."
  value       = proxmox_virtual_environment_vm.worker[*].vm_id
}

output "worker_ipv4_addresses" {
  description = <<-EOT
    qemu-guest-agent 가 보고한 IP. 에이전트가 뜨기 전에는 비어 있을 수 있다.
    이 값을 hosts.ini 에 적지 않는다 — 인벤토리는 태그로 굴러간다.
    사람이 눈으로 확인할 때만 쓴다.
  EOT
  value       = proxmox_virtual_environment_vm.worker[*].ipv4_addresses
}
