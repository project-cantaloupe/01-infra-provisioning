terraform {
  # backend.tf 의 use_lockfile 이 1.10 부터다.
  required_version = ">= 1.10"

  required_providers {
    # telmate/proxmox 가 아니라 bpg/proxmox 를 쓴다 (telmate 는 방치 상태).
    # 인벤토리(ansible/inventories/onprem/proxmox.yaml)의 주석과 같은 이유다.
    # ~> 0.111 은 >= 0.111, < 1.0 이다. 0.x 대는 아직 리소스 이름이 바뀌는 중이라
    # (v1.0 에서 proxmox_virtual_environment_* 접두사가 사라진다) 상한을 1.0 으로 막는다.
    # 실제로 쓰는 버전은 .terraform.lock.hcl 이 고정한다.
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}
