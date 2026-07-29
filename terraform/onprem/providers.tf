provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  # snippets(cloud-init user-data) 업로드는 API 가 아니라 SSH 로 나간다.
  # 이 블록이 없으면 proxmox_virtual_environment_file 이 실패한다.
  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
