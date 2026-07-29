locals {
  worker_names = [
    for i in range(var.worker_count) :
    format("%s-%02d", var.worker_name_prefix, i + 1)
  ]

  use_dhcp = length(var.worker_ipv4_addresses) == 0
}

# ── OS 이미지 ───────────────────────────────────────────────────
# 손으로 만든 템플릿을 clone 하지 않는다. 템플릿은 코드 밖에 있어서
# "어떤 상태였는지"가 상태 파일에도 git 에도 안 남는다.

resource "proxmox_download_file" "os_image" {
  content_type       = "iso"
  datastore_id       = var.image_datastore_id
  node_name          = var.proxmox_node
  url                = var.os_image_url
  file_name          = var.os_image_file_name
  checksum           = var.os_image_checksum
  checksum_algorithm = "sha256"
  overwrite          = false
}

# ── cloud-init user-data ────────────────────────────────────────
# VM 마다 hostname 이 달라서 파일도 VM 마다 하나씩 만든다.

resource "proxmox_virtual_environment_file" "cloud_config" {
  count = var.worker_count

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${local.worker_names[count.index]}-cloud-config.yaml"
    data = templatefile("${path.module}/cloud-init/worker.yaml.tftpl", {
      hostname        = local.worker_names[count.index]
      username        = var.vm_username
      ssh_public_keys = var.ssh_public_keys
    })
  }
}

# ── 워커 VM ─────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "worker" {
  count = var.worker_count

  name      = local.worker_names[count.index]
  node_name = var.proxmox_node
  vm_id     = var.worker_vmid_base + count.index

  description = "K8s worker (area=onprem). Terraform 이 관리한다. 손으로 고치지 않는다."

  # Proxmox 태그는 key=value 를 못 쓴다. 하이픈으로 붙이고
  # ansible 이 그대로 그룹 이름으로 읽는다 (- 는 _ 로 변환된다).
  #   area-onprem  → area_onprem
  #   role-worker  → role_worker   ← site-workers.yaml 의 hosts 가 이것이다
  tags = ["area-onprem", "role-worker"]

  # destroy 시 정지부터 한다. 안 그러면 락이 걸린 채로 실패한다.
  stop_on_destroy = true

  agent {
    enabled = true
  }

  cpu {
    cores = var.worker_cpu
    # 홈랩이고 마이그레이션 대상이 없다. 호스트 CPU 기능을 그대로 노출한다.
    type = "host"
  }

  memory {
    dedicated = var.worker_memory
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_datastore_id
    file_id      = proxmox_download_file.os_image.id
    interface    = "scsi0"
    size         = var.worker_disk
    # NVMe 라 TRIM 을 흘려보낸다. 씬 프로비저닝이면 실제 사용량만 먹는다.
    discard  = "on"
    ssd      = true
    iothread = true
  }

  initialization {
    datastore_id = var.vm_datastore_id
    interface    = "ide2"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = local.use_dhcp ? "dhcp" : var.worker_ipv4_addresses[count.index]
        gateway = local.use_dhcp ? null : var.ipv4_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config[count.index].id
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_vlan_id
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    precondition {
      condition     = local.use_dhcp || length(var.worker_ipv4_addresses) == var.worker_count
      error_message = "worker_ipv4_addresses 는 비우거나(DHCP) worker_count 와 같은 개수여야 한다."
    }

    precondition {
      condition     = local.use_dhcp || var.ipv4_gateway != null
      error_message = "고정 IP 를 쓰면 ipv4_gateway 를 지정해야 한다."
    }
  }
}
