terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- 가이드라인 토큰 표준 라벨 (org: cntlp) ---
locals {
  common_labels = {
    org        = "cntlp"
    owner      = "team-platform"
    managed-by = "terraform"
    data-class = "internal"
    lifecycle  = "permanent"
    platform   = "gcp"
  }

  # --- 통합 스타트 스크립트 (K8s v1.36.3 & OS 초기 세팅) ---
  startup_script = <<-EOT
#!/bin/bash
set -e

# 1. OpenSearch 실행 필수 커널 메모리 설정
sysctl -w vm.max_map_count=262144
if ! grep -qs "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

# 2. Swap 메모리 비활성화 (K8s 필수)
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

# 3. K8s CNI 필수 커널 모듈 로드
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 4. K8s 필수 커널 파라미터(sysctl) 및 IP Forwarding 설정
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# 5. OS 패키지 최신화 및 필수 유틸리티 설치
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release net-tools htop jq git containerd

# 6. containerd 설정 및 SystemdCgroup 적용
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# 7. 타임존 설정 (KST)
timedatectl set-timezone Asia/Seoul

# 8. Kubernetes v1.36.3 공식 패키지 설치
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet=1.36.3-1.1 kubeadm=1.36.3-1.1 kubectl=1.36.3-1.1
apt-mark hold kubelet kubeadm kubectl
EOT
}

# --- 네트워크 및 서브넷 ---
resource "google_compute_network" "vpc" {
  name                    = "cntlp-gcp-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "cntlp-gcp-subnet"
  ip_cidr_range = "10.0.10.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# --- Cloud Router & Cloud NAT ---
resource "google_compute_router" "router" {
  name    = "cntlp-gcp-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "cntlp-gcp-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- 방화벽 규칙 ---
resource "google_compute_firewall" "allow_internal" {
  name    = "cntlp-gcp-fw-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.10.0/24"]
}

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "cntlp-gcp-fw-allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# --- 영구 디스크 (K8s CSI 연동용 독립 자원) ---
resource "google_compute_disk" "metrics_disk" {
  name = "cntlp-gcp-metrics-disk"
  type = "pd-standard"
  size = 150
  zone = var.zone
  labels = merge(local.common_labels, {
    component = "metrics"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# --- Compute Engine 인스턴스 (Worker Node 01 - e2-custom-4-8192) ---
resource "google_compute_instance" "worker_node_01" {
  name         = "cntlp-gcp-wk-01"
  machine_type = "e2-custom-4-8192" # vCPU 4개, 메모리 8GB
  zone         = var.zone
  labels = merge(local.common_labels, {
    role = "monitoring"
  })
  can_ip_forward = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 100
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = local.startup_script
}

# --- Compute Engine 인스턴스 (Worker Node 02 - e2-standard-4) ---
resource "google_compute_instance" "worker_node_02" {
  name         = "cntlp-gcp-wk-02"
  machine_type = "e2-standard-4" # vCPU 4개, 메모리 16GB
  zone         = var.zone
  labels = merge(local.common_labels, {
    role = "logging"
  })
  can_ip_forward = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 100
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = local.startup_script
}
