# terraform/onprem

Proxmox 호스트 위에 **K8s 워커 VM** 을 만든다. 컨트롤플레인은 여기 없다 —
마스터 3대는 전부 AWS 에 있다.

## 만들어지는 것

| 리소스 | 내용 |
|---|---|
| `proxmox_download_file.os_image` | Ubuntu 24.04 cloud image. 손으로 만든 템플릿에 의존하지 않는다 |
| `proxmox_virtual_environment_file.cloud_config` | VM 별 cloud-init user-data (계정·SSH 키·qemu-guest-agent) |
| `proxmox_virtual_environment_vm.worker` | 워커 VM. 기본 1대 / 8 vCPU / 16GB / 120GB |

VM 에는 `area-onprem`, `role-worker` 태그가 붙는다.
**이 태그가 곧 ansible 그룹이다.** 손으로 IP 를 적지 않는 이유가 이것이다.

## 먼저 해둘 것

### 1. API 토큰

```bash
pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Administrator
pveum user token add terraform@pve provisioning --privsep 0
```

출력된 `full-tokenid` 와 `value` 를 `terraform.tfvars` 의 `proxmox_api_token` 에
`user@realm!tokenid=uuid` 형식으로 합쳐 넣는다.

ansible 인벤토리도 같은 토큰을 쓴다. 환경변수로도 내보낸다:

```bash
export PROXMOX_URL=https://192.168.0.10:8006/
export PROXMOX_USER=terraform@pve
export PROXMOX_TOKEN_ID=provisioning
export PROXMOX_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 2. snippets 콘텐츠 타입

cloud-init user-data 는 snippet 으로 올라간다. 스토리지에 이 타입이 꺼져 있으면
`proxmox_virtual_environment_file` 이 실패한다.

**Datacenter → Storage → (해당 스토리지) → Edit → Content 에 `Snippets` 추가**

### 3. SSH 접근 — 여기서 한 번 막힌다

snippets 업로드는 API 가 아니라 **SSH 로 나간다**. 이미지 다운로드까지는 API 로 되므로
`terraform apply` 가 절반쯤 성공한 뒤 여기서 멈춘다.

**provider 는 `~/.ssh/config` 를 보지 않는다.** 에러 메시지가 직접 그렇게 말한다 —

> unable to authenticate user "root" over SSH ...
> (NOTE: configurations in ~/.ssh/config are not considered by the provider)

`Host` 별칭도 `IdentityFile` 도 안 먹는다. `providers.tf` 의 `ssh { agent = true }` 는
**ssh-agent 에 올라온 키만** 본다. 따라서 두 가지가 모두 필요하다.

```bash
# 1. 키가 agent 에 올라와 있어야 한다
ssh-add ~/.ssh/cantaloupe_ed25519
ssh-add -l

# 2. 그 키가 Proxmox 호스트에 등록돼 있어야 한다 (root 비밀번호를 묻는다)
ssh-copy-id -i ~/.ssh/cantaloupe_ed25519.pub root@<proxmox-ip>

# 3. 확인 — 비밀번호를 안 물어야 한다
ssh -o BatchMode=yes root@<proxmox-ip> hostname
```

3번이 통과하지 않으면 apply 는 반드시 같은 지점에서 멈춘다.

### 4. 이미지 체크섬

```bash
curl -s https://cloud-images.ubuntu.com/noble/current/SHA256SUMS \
  | grep noble-server-cloudimg-amd64.img
```

`os_image_checksum` 에 넣는다. 기본값을 두지 않았다 —
같은 URL 이 시간이 지나면 다른 내용을 가리키기 때문이다.

## 실행

`backend.tf` 가 S3 를 쓰므로 `terraform init` 은 AWS 자격증명과
`cantaloupe-tfstate` 버킷을 요구한다. 문법만 볼 거면 백엔드를 건너뛴다.

```bash
# 코드가 맞는지만 확인 (버킷·자격증명 불필요)
terraform init -backend=false
terraform fmt -check -diff
terraform validate

# 실제로 만든다
cp terraform.tfvars.example terraform.tfvars   # 채운다
terraform init          # -backend=false 로 먼저 돌렸다면 -reconfigure
terraform plan
terraform apply
```

`.terraform.lock.hcl` 은 **커밋한다.** provider 버전이 실행자마다
달라지는 걸 막는 유일한 장치다.

### plan 파일과 로그는 리포에 두지 않는다

`terraform plan -out=tfplan` 의 산출물은 **암호화되지 않은 zip 이다.**
`sensitive = true` 로 가린 값도 그대로 들어간다 — 이 디렉터리의 tfplan 에서
실제로 `proxmox_api_token` 이 평문으로 나왔다.

```bash
terraform show -json tfplan | jq '.variables | keys'   # 변수가 통째로 들어있다
```

`tfplan`, `*.log` 는 `.gitignore` 에 있다. 남길 기록은 리포가 아니라 여기가 갖는다.

| 남길 것 | 어디에 |
|---|---|
| plan/apply 출력 | CI 잡 로그 (Actions·Atlantis PR 코멘트) |
| 누가 언제 뭘 바꿨나 | 백엔드의 state 버전 이력 (S3 버저닝) |
| 디버그 로그 | `TF_LOG=DEBUG TF_LOG_PATH=/tmp/tf.log` — 볼 때만 켜고 버린다 |

plan 파일이 필요한 곳은 CI 의 plan→apply 승인 흐름 하나뿐이고,
거기서도 커밋이 아니라 **빌드 아티팩트**로 넘긴다.

## provider 버전 주의

`bpg/proxmox` 는 아직 0.x 이고 **v1.0 에서 `proxmox_virtual_environment_*` 접두사를 없앤다.**
`versions.tf` 의 제약을 `< 1.0` 으로 막아둔 이유다.

v0.111 기준 이미 갈린 것:

| 쓰는 것 | 상태 |
|---|---|
| `proxmox_download_file` | 새 이름. 이걸 쓴다 |
| `proxmox_virtual_environment_download_file` | deprecated |
| `proxmox_virtual_environment_file` | 아직 현행. 새 이름 없음 |
| `proxmox_virtual_environment_vm` | 아직 현행 (속성 40개) |
| `proxmox_vm` | **위의 새 이름이 아니다.** 구 `vm2` 의 새 이름이고 속성이 14개뿐 |

## 다음

VM 이 뜬 뒤 ansible 이 잡는지부터 확인한다. **여기서 자주 끊긴다.**

```bash
ansible-inventory -i ../../ansible/inventories/onprem/proxmox.yaml --graph
```

`@role_worker` 아래에 방금 만든 VM 이 보여야 한다.
안 보이면 `proxmox.yaml` 에 `keyed_groups` 가 없어서다 — `site-workers.yaml` 이
`hosts: role_worker` 로 잡으므로, 그룹이 안 만들어지면 **에러 없이 조용히 건너뛴다.**

## 사이징을 왜 1대로 몰았나

물리 호스트가 1대(Ryzen 5 5600U 6c/12t · 24GB · 256GB NVMe)다.
VM 을 쪼개도 호스트가 죽으면 같이 죽으므로 가용성은 안 늘고,
kubelet·containerd·Calico 오버헤드만 중복된다.
Harbor 스토리지를 한 노드에 몰아 쓸 수 있어 디스크 병목도 늦게 온다.

디스크가 120GB 인 이유는 따로 있다. 256GB NVMe 는 기본 설치에서
`local`(디렉터리, 67GB) 과 `local-lvm`(lvmthin, 140GB) 으로 쪼개진다.
VM 디스크는 `local-lvm` 에서만 나오므로 상한이 256 이 아니라 **140** 이다.
lvmthin 은 오버프로비저닝이 되지만 풀이 차면 파일시스템이 깨지므로 넘기지 않는다.
