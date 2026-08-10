# 환경에 따라 달라지는 값은 전부 여기로 뺀다.
# .gitignore 가 *.tfvars 를 제외하므로 실제 값은 terraform.tfvars 에 넣고
# 형식은 terraform.tfvars.example 을 본다.

# ── Proxmox 접속 ────────────────────────────────────────────────
#
# **proxmox_endpoint 와 proxmox_api_token 은 변수가 아니다.** Vault 의
# secret/onp/proxmox 에서 온다 — vault.tf.
#
# 여기 변수로 남겨두고 tfvars 를 선택지로 두지 않는 이유는, 폴백이 있으면
# 사람이 결국 쉬운 길로 가기 때문이다. 없애야 없어진다
# → tasks/done/006_vault-setup.md 8절
#
# 아래 둘은 시크릿이 아니라 접속 방식이라 그대로 변수다.

variable "proxmox_insecure" {
  description = "자체서명 인증서를 허용할지. 홈랩 기본값은 true 다."
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "snippets 업로드에 쓸 SSH 계정. 보통 root."
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "VM 을 올릴 Proxmox 노드 이름. `pvesh get /nodes` 로 확인한다."
  type        = string
}

# ── 데이터스토어 ────────────────────────────────────────────────

variable "vm_datastore_id" {
  description = "VM 디스크와 cloud-init 드라이브를 둘 스토리지. 예: local-lvm"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore_id" {
  description = "OS 이미지를 받아둘 스토리지. `iso` 콘텐츠 타입이 켜져 있어야 한다."
  type        = string
  default     = "local"
}

variable "snippet_datastore_id" {
  description = <<-EOT
    cloud-init user-data 를 둘 스토리지.
    해당 스토리지에 `snippets` 콘텐츠 타입이 켜져 있어야 한다.
    (Datacenter → Storage → Edit → Content 에 Snippets 추가)
  EOT
  type        = string
  default     = "local"
}

# ── OS 이미지 ───────────────────────────────────────────────────

variable "os_image_url" {
  description = "cloud image URL. 미리 만들어둔 템플릿에 의존하지 않기 위해 terraform 이 직접 받는다."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "os_image_file_name" {
  description = "저장될 파일명. iso 콘텐츠 타입은 확장자가 .img 또는 .iso 여야 한다."
  type        = string
  default     = "noble-server-cloudimg-amd64.img"
}

variable "os_image_checksum" {
  description = <<-EOT
    이미지의 sha256. 같은 URL 이 시간이 지나면 다른 내용을 가리키므로 고정한다.
    `curl -s https://cloud-images.ubuntu.com/noble/current/SHA256SUMS | grep noble-server-cloudimg-amd64.img`
    기본값을 두지 않는다 — 틀린 값을 물려받는 것보다 한 번 붙여넣는 편이 낫다.
  EOT
  type        = string
}

# ── 워커 VM ─────────────────────────────────────────────────────
# 사이징 근거는 README 의 "사이징을 왜 1대로 몰았나" 에 있다.
# 물리 호스트가 1대(6c/12t · 24GB · 256GB)라 VM 을 쪼개도 가용성은 안 늘고
# kubelet·containerd·Calico 오버헤드만 중복된다. 1대로 몰고 호스트에 여유를 남긴다.

variable "worker_count" {
  description = "워커 VM 개수."
  type        = number
  default     = 1
}

variable "worker_name_prefix" {
  description = <<-EOT
    VM 이름 접두사. 뒤에 -01, -02 가 붙고 **그대로 K8s 노드 이름이 된다.**

    명명 규칙은 cntlp-<platform>-wk-<nn> 다 (decisions/20260729_resource-naming-convention).
    org 를 cantaloupe 가 아니라 cntlp 로 줄인 것은 GCP 서비스 계정 30자 제한과
    S3 버킷 이름 유일성 때문이다.

    조인 후에 바꾸면 노드 이름이 곧 K8s 오브젝트 이름이라 drain·delete·rejoin 이
    필요하다. 조인 전에 확정한다.
  EOT
  type        = string
  default     = "cntlp-onp-wk"
}

variable "worker_vmid_base" {
  description = "첫 VM 의 VMID. 이후 순차 증가한다."
  type        = number
  default     = 210
}

variable "worker_cpu" {
  description = "vCPU 수. 호스트가 6c/12t 이므로 4를 Proxmox 에 남긴다."
  type        = number
  default     = 8
}

variable "worker_memory" {
  description = "메모리(MiB). 호스트가 24GB 이므로 8GB 를 남긴다."
  type        = number
  default     = 16384
}

variable "worker_disk" {
  description = <<-EOT
    디스크(GiB). Harbor 가 여기를 먹는다.

    "256GB 니까 180GB" 가 아니다. Proxmox 기본 설치가 디스크를
    local(dir, 67GB)  과 local-lvm(thin, 140GB) 로 갈라 가져간다.
    **VM 디스크로 쓸 수 있는 것은 local-lvm 쪽 140GB 뿐이다.**
    thin pool 이 꽉 차면 그 위 VM 들의 파일시스템이 깨지므로 여유를 남긴다.
  EOT
  type        = number
  default     = 120
}

variable "vm_username" {
  description = "ansible 이 SSH 로 붙을 계정. cloud-init 이 만든다."
  type        = string
  default     = "ubuntu"
}

# **ssh_public_keys 도 변수가 아니다.** Vault 의 secret/ssh/cntlp-public 에서
# 온다 — vault.tf 의 local.ssh_public_keys.
#
# 공개키는 비밀이 아닌데 왜 Vault 에 두느냐 — 배포 대상을 한 곳에서 갈아끼우기
# 위해서다. 키를 교체할 때 tfvars·인벤토리·문서에 흩어진 사본을 전부 찾아
# 고치는 대신 KV 한 경로만 쓴다. 그리고 개인키와 **다른 경로**에 둔 것이
# terraform-onp 정책이 개인키를 막을 수 있는 이유다 (2절).

# ── 네트워크 ────────────────────────────────────────────────────

variable "network_bridge" {
  description = "붙일 브리지. 홈랩 기본값은 vmbr0."
  type        = string
  default     = "vmbr0"
}

variable "network_vlan_id" {
  description = "VLAN 태그. 안 쓰면 null."
  type        = number
  default     = null
}

variable "worker_ipv4_addresses" {
  description = <<-EOT
    워커의 고정 IP 를 CIDR 로 적는다. 예: ["192.168.0.51/24"]
    비워두면 DHCP 를 쓴다. K8s 노드는 IP 가 바뀌면 곤란하므로
    DHCP 를 쓸 거면 공유기에서 MAC 예약을 걸어둔다.
    비우지 않을 거면 worker_count 와 개수가 같아야 한다.
  EOT
  type        = list(string)
  default     = []
}

variable "ipv4_gateway" {
  description = "게이트웨이. worker_ipv4_addresses 를 쓸 때만 의미가 있다."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS 서버 목록."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}
