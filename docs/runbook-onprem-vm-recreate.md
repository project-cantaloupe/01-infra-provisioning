# 런북 — 온프렘 워커 VM 삭제·재생성·재조인

Proxmox 워커 VM을 지우고 다시 만들어 K8s 클러스터에 재조인하는 절차.

**여러 번 돌려도 같은 결과가 나오는 것이 목표다.** 어디까지 그게 성립하고
어디부터 사람이 개입해야 하는지를 먼저 적는다. 순서만 필요하면
[전체 순서](#전체-순서)로 바로 간다.

대상: `cntlp-onp-wk-01` / VMID 210 / `192.168.0.51` / Proxmox 노드 1대.

---

## 1. 멱등적인 것 — 그냥 다시 돌리면 된다

| 무엇 | 왜 성립하나 |
|---|---|
| VMID | `worker_vmid_base + count.index` = 210 고정 |
| IP 주소 | `worker_ipv4_addresses = ["192.168.0.51/24"]` 고정. DHCP 리스 드리프트가 없다 |
| VM 이름 | `worker_name_prefix` + `-01` = `cntlp-onp-wk-01`. **그대로 K8s 노드 이름이 된다** |
| destroy 안정성 | `stop_on_destroy = true`. 정지부터 하므로 락이 걸린 채 실패하지 않는다 |
| cloud-init | 스니펫도 terraform 리소스라 VM과 함께 재생성된다 |
| OS 이미지 | 별도 리소스. VM만 `-target` destroy 하면 재다운로드하지 않는다 |
| ansible 인벤토리 | 태그(`platform-onp`)로 굴러간다. **IP를 어디에도 적지 않는다** |
| SSH 호스트 키 변경 | `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null`로 흡수된다 |
| OS 준비 롤 | `common`·`containerd`는 재실행 안전 |
| 조인 롤 | 조인 상태를 4가지로 판정한다 ([3절](#3-조인-상태-판정)) |

## 2. 멱등적이지 **않은** 것 — 사람이 해야 한다

이 4개가 이 런북이 존재하는 이유다. terraform으로 해결되지 않는다.

### 2-1. 클러스터의 Node 오브젝트는 VM을 지워도 남는다

etcd에 있는 것이라 Proxmox와 무관하다. 지우지 않고 재조인하면 낡은 인증서·컨디션이
남은 Node에 새 노드가 겹친다.

**워커에서 자동화할 수 없다.** 워커에는 admin kubeconfig가 없다
(`/etc/kubernetes/kubelet.conf`는 kubelet 전용 자격증명이다). 워커가 자기 Node를
지우는 것은 권한 경계를 넘는 일이기도 하다. 그래서 사람이 워크스테이션에서 먼저 한다.

### 2-2. tailnet 디바이스도 VM을 지워도 남는다

새 VM은 machine key가 새것이라 Tailscale이 **같은 이름의 디바이스를 하나 더** 만들고,
이름이 겹치므로 뒤에 `-1`을 붙인다. 그러면 메시 이름과 IP가 이전과 달라지고
`kubeadm join --node-ip`가 바뀐다.

`vpn-mesh` 롤이 이걸 검사해서 멈춘다(조용히 지나가지 않는다). 근본 해결은
**auth key를 ephemeral로 발급**하는 것이다 — 오프라인이 되면 Tailscale이 스스로 지운다.

### 2-3. bootstrap 토큰은 24시간이면 만료된다

재조인마다 컨트롤플레인에서 새로 발급해야 한다. 만료된 토큰으로 조인하면
타임아웃으로만 드러난다.

### 2-4. tfstate가 아직 로컬이다

`terraform/onprem/backend_override.tf`가 S3 백엔드를 우회하고 있다. **다른 PC에서는
destroy할 수 없다.** AWS가 서면 정리한다.

```bash
rm terraform/onprem/backend_override.tf
terraform -chdir=terraform/onprem init -migrate-state
```

### 2-5. VM 안의 데이터는 전부 사라진다 (현재)

`decisions/20260729_onprem-storage-allocation`은 Harbor blob과 `JENKINS_HOME`을
호스트 전용 LV(`cntlp-data`)에 두고 kubelet이 NFS로 마운트하도록 정했다.
**그 LV와 export는 아직 만들지 않았다** — 지금 구현된 것은 `nfs-common` 설치뿐이다.

즉 **현재 시점에서 VM을 지우면 그 안의 모든 것이 사라진다.** Harbor·Jenkins를
올린 뒤라면 이 런북을 그대로 쓰기 전에 스토리지 결정을 먼저 구현한다.

---

## 3. 조인 상태 판정

`kubeadm-worker` 롤은 **"kubelet.conf가 있으면 조인됨"으로 판정하지 않는다.**
그 파일은 클러스터를 다시 세워도 남기 때문이다. 파일 안의 `server:` URL을 읽어
어디에 붙어 있는지를 본다.

| 상태 | 조건 | 동작 |
|---|---|---|
| 깨끗함 | 조인 흔적 없음 | 조인한다 |
| 일치 | 기대 엔드포인트에 붙어 있음 | **건너뛴다** (멱등) |
| 불일치 | 다른 엔드포인트에 붙어 있음 | 멈추고 안내한다 |
| 더러움 | `kubelet.conf`는 없는데 `pki/ca.crt`나 `kubelet/config.yaml`이 남음 | 멈추고 안내한다 |

`불일치`·`더러움`을 넘기려면 `-e kubeadm_force_rejoin=true`를 준다. **그때만**
`kubeadm reset -f`와 `/etc/cni/net.d` 삭제가 돈다. 기본값으로는 아무것도 지우지 않는다.

`iptables`는 어떤 경우에도 건드리지 않는다. `kubeadm reset`도 안 건드린다고 경고한다 —
SSH로 붙어 있는 상태에서 규칙을 밀면 세션이 끊기고 ufw 규칙까지 날아간다.
VM을 유지한 채 재조인해서 파드 네트워킹이 이상하면 **재부팅**이 안전한 방법이다.

---

## 전체 순서

### 0. 환경

```bash
cd repos/01-infra-provisioning
source scripts/cantaloupe-env.sh     # source 로 불러야 한다
```

### 1. 클러스터에서 노드를 뺀다

**VM을 지우기 전에 한다.** 순서가 바뀌면 drain이 도달 불가로 실패한다.

```bash
kubectl drain cntlp-onp-wk-01 --ignore-daemonsets --delete-emptydir-data
kubectl delete node cntlp-onp-wk-01
kubectl get nodes                     # 사라졌는지 확인
```

컨트롤플레인이 아직 없으면 이 단계를 건너뛴다(뺄 것이 없다).

### 2. tailnet 디바이스를 지운다

Tailscale admin 콘솔 → Machines → `cntlp-onp-wk-01` → Remove.

ephemeral 키로 등록했다면 오프라인 후 자동으로 사라지므로 건너뛴다.

### 3. VM을 지운다

```bash
# 빠른 경로 — VM만 지운다. OS 이미지(약 600MB)를 다시 받지 않는다
terraform -chdir=terraform/onprem destroy -target='proxmox_virtual_environment_vm.worker'

# 전부 지우려면 (이미지·스니펫까지)
terraform -chdir=terraform/onprem destroy
```

### 4. VM을 다시 만든다

```bash
terraform -chdir=terraform/onprem plan     # 반드시 눈으로 본다
terraform -chdir=terraform/onprem apply
```

### 5. 인벤토리가 잡는지 확인한다 — **여기서 자주 끊긴다**

```bash
cd ansible
ansible-inventory --graph
```

`@platform_onp`와 `@role_devops` 아래에 VM이 보여야 한다. 안 보이면
`qemu-guest-agent`가 아직 안 떴거나(1~2분 기다린다) Proxmox 태그가 빠진 것이다.

```bash
ansible platform_onp -m ping     # 플래그 없이 pong 이어야 한다
```

**플래그(`-u`, `--private-key`)를 붙여야 통과한다면 통과한 게 아니다.**
`group_vars`가 제 역할을 못 하는 상태이고, 플레이북·CI에서는 실패한다.

### 6. OS를 준비한다

```bash
ansible-playbook playbooks/site-workers.yaml --tags common
ansible-playbook playbooks/site-workers.yaml --tags containerd
```

`security-hardening`은 **조인의 전제가 아니다.** ufw를 켜므로 온프렘 VM 1대에
SSH로 붙어 있는 동안에는 미룬다. 돌릴 때는 Proxmox 콘솔을 열어둔다.

```bash
ansible-playbook playbooks/site-workers.yaml --tags security   # 나중에
```

> `--check`는 이 롤들에서 신뢰할 수 없다. `command`/`shell` 태스크가 스킵되면
> 뒤의 assert가 연쇄 실패해서 진짜 문제와 구분되지 않는다.

### 7. 메시에 붙인다

```bash
TAILSCALE_AUTH_KEY=tskey-auth-... \
  ansible-playbook playbooks/site-workers.yaml --tags mesh
```

이름이 `-1` 붙어 등록되면 롤이 멈춘다. 2단계(디바이스 삭제)를 건너뛴 것이다.

### 8. 조인한다

컨트롤플레인에서 토큰을 발급한다.

```bash
kubeadm token create --print-join-command
```

출력을 통째로 넘긴다.

```bash
./scripts/join-worker.sh --check-only \
  --join-command "kubeadm join 100.x.x.x:6443 --token ... --discovery-token-ca-cert-hash sha256:..."

./scripts/join-worker.sh \
  --join-command "kubeadm join 100.x.x.x:6443 --token ... --discovery-token-ca-cert-hash sha256:..."
```

`--check-only`가 먼저다. 노드를 건드리기 전에 도달성·버전·인벤토리를 본다.

### 9. 확인한다

```bash
kubectl get nodes -o wide
kubectl get node cntlp-onp-wk-01 --show-labels    # platform=onp, role=devops
```

**CNI가 아직이면 `NotReady`가 정상이다.**

---

## VM을 유지하고 재조인만 하기

클러스터를 다시 세웠는데 VM은 그대로 두고 싶을 때.

```bash
# 1. 클러스터에서 노드를 뺀다 (위 1단계와 같다)
kubectl drain cntlp-onp-wk-01 --ignore-daemonsets --delete-emptydir-data
kubectl delete node cntlp-onp-wk-01

# 2. reset 하고 재조인한다
KUBEADM_API_ENDPOINT=... KUBEADM_TOKEN=... KUBEADM_CA_CERT_HASH=... \
  ansible-playbook playbooks/site-workers.yaml --tags join \
  -e kubeadm_force_rejoin=true

# 3. 파드 네트워킹이 이상하면 재부팅한다 (kube-proxy 잔여 iptables 규칙)
ansible platform_onp -m reboot -b
```

VM을 다시 만드는 쪽이 더 깨끗하다. 흔적이 애초에 없다.

---

## 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| `ansible-inventory --graph`가 호스트 0개 | `PROXMOX_*` 미설정, `python3-proxmoxer` 없음 | `source scripts/cantaloupe-env.sh` |
| `@platform_onp` 그룹이 없다 | Proxmox 태그 누락 | `tags = ["platform-onp", "role-devops"]` 확인 |
| `Permission denied (publickey)` | `group_vars` 미적용 | 플래그 없이 `ansible platform_onp -m ping` 재확인 |
| VM에 IP가 안 보인다 | `qemu-guest-agent` 미기동 | 1~2분 대기. cloud-init 로그 확인 |
| `FileAvailable--etc-kubernetes-pki-ca.crt` | 더러움 상태 | `-e kubeadm_force_rejoin=true` |
| 롤이 "다른 클러스터에 붙어 있다"고 멈춘다 | 불일치 상태 | 위 [재조인](#vm을-유지하고-재조인만-하기) |
| tailnet 이름에 `-1`이 붙었다 | 죽은 디바이스 잔존 | admin 콘솔에서 삭제. ephemeral 키로 전환 |
| 조인이 타임아웃만 남기고 죽는다 | 토큰 만료·버전 불일치·도달 불가 | `join-worker.sh --check-only`로 먼저 가른다 |
| 조인 실패 원인이 안 보인다 | 토큰 보호용 `no_log: true` | 워커에서 직접 `kubeadm join ... -v=5` |

---

## 아직 자동화되지 않은 것

정직하게 남긴다. 자동화 후보이지 버그가 아니다.

- **`kubectl drain`·`delete node`** — 워커에 admin kubeconfig가 없어 롤에서 못 한다.
  워크스테이션에서 도는 플레이북(`delegate_to: localhost`)으로 옮길 수 있다.
  컨트롤플레인이 서기 전에는 검증할 수 없어 아직 하지 않았다
- **tailnet 디바이스 삭제** — Tailscale API 키가 필요하다. ephemeral 키를 쓰면
  애초에 필요 없어지므로 그쪽이 낫다
- **`join-worker.sh`의 사전 점검** — 대부분 ansible로 표현된다(`wait_for`, `uri`,
  `assert`). 지금은 preflight가 스크립트와 롤 두 층으로 나뉘어 있다
- **이 런북 전체를 한 명령으로** — 위 2절의 4개가 사람 판단을 요구하는 동안은
  묶지 않는 편이 낫다. 특히 `drain`은 되돌릴 수 없다

## 검증 상태

**컨트롤플레인이 없어 8·9단계는 실행 검증되지 않았다.** 3절의 상태 판정 로직은
네 상태 + `force` 경로를 시뮬레이션으로 확인했고, 롤은 문법·파싱 검증을 통과했다.
1~7단계는 실제 실행으로 검증되면 이 문단을 고친다.
