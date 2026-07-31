# 런북 — 전체 구축 순서

**아무것도 없는 상태에서 멀티클라우드 + 온프렘 클러스터까지 세우는 순서.**

각 단계는 앞 단계의 산출물을 요구한다. 순서를 바꾸면 대부분 조용히 실패한다 —
에러가 아니라 "0개 처리하고 성공" 으로 끝나는 형태다. **왜 이 순서인지**를
같이 적는 이유다.

이미 서 있는 것을 고치는 절차는 각 런북에 있다. 이 문서는 처음부터 세우는 순서다.

| 알고 싶은 것 | 어디 |
|---|---|
| 시크릿을 새로 넣고 쓰려면 | [`runbook-secrets.md`](runbook-secrets.md) |
| 팀원이 합류하려면 | [`runbook-onboarding.md`](runbook-onboarding.md) |
| Vault 를 고치려면 | [`runbook-vault.md`](runbook-vault.md) |
| 상태 버킷·키를 다시 만들려면 | [`runbook-tfstate.md`](runbook-tfstate.md) |
| 온프렘 VM 을 다시 만들려면 | [`runbook-onp-vm-recreate.md`](runbook-onp-vm-recreate.md) |

---

## 한눈에

```
0  워크스테이션                     사람이 손으로
   ↓
1  tfstate 버킷 + KMS 키            terraform 밖에서 손으로   ← 순환 회피
   ↓
2  aws/network → aws/egress         VPC·서브넷·EICE·NAT
   ↓
3  aws/vault → site-vault.yaml      Vault 서버가 뜬다
   → operator init                  ← 사람만. 봉투에 봉인
   → terraform/vault                정책·AppRole·감사
   → 시크릿 투입                     ← 사람만
   ↓
4  aws/compute · gcp · onp          노드 VM 을 만든다   ← onp 는 Vault 를 읽는다
   ↓
5  site-cluster.yaml                kubeadm 클러스터가 선다
   ↓
6  aws/database · ArgoCD            그 위에 얹는 것
```

**3단계가 4단계보다 앞인 이유** — `terraform/onp` 이 Proxmox 토큰을 Vault 에서
읽는다. Vault 가 없으면 온프렘 노드를 만들 수 없다. AWS·GCP 노드만이라면
Vault 없이도 되지만, 그렇게 하면 나중에 Vault 를 세운 뒤 이미 만든 것들을
다시 손봐야 한다.

**2단계의 `egress` 를 빼먹으면 3단계가 통째로 막힌다.** Vault EC2 는 Private
Subnet 에 있어서 NAT 없이는 apt 도 tailnet 조인도 못 한다.

---

## 0. 워크스테이션

```bash
git clone <repo> && cd 01-infra-provisioning
./scripts/bootstrap-workstation.sh
```

이게 넣는 것 — `terraform`(≥1.10), `ansible`, `aws`, `vault`, `kubectl`,
`tailscale`. 컬렉션은 따로 받는다.

```bash
cd ansible && ansible-galaxy collection install -r requirements.yml && cd ..
```

**필요한 것 셋.** 이 시점에는 Vault 가 없으므로 전부 손으로 준비한다.

| 무엇 | 어떻게 |
|---|---|
| AWS 자격증명 | `aws login` — **축소 불가능한 secret-zero 다** |
| Tailscale auth key | admin 콘솔 → Settings → Keys. reusable + 태그 부여 권한 |
| SSH 키 한 쌍 | `ssh-keygen -t ed25519 -C cantaloupe-infra` |

Tailscale 키의 태그 조건이 중요하다. tailnet ACL 의 `tagOwners` 에 없는 태그로
가입하려 하면 `tailscale up` 이 `requested tags are invalid or not permitted`
로 죽는다. 필요한 태그는 넷이다.

```
tag:cntlp-aws-cp     컨트롤플레인
tag:cntlp-wk         워커 (AWS·GCP·온프렘 공통)
tag:cntlp-vault      Vault 노드
tag:cntlp-router     서브넷 라우터
```

**ACL 에 그 태그로 들어오는 트래픽 규칙이 없으면 노드는 뜨는데 아무도 닿지
못한다.** `tailscale up` 자체는 성공해서 실패로 보이지 않는다.

---

## 1. tfstate 버킷과 KMS 키

**terraform 으로 만들지 않는다.** 만들면 그 스택의 상태가 자기가 만든 자원
안에 들어간다. 절차 전문은 [`runbook-tfstate.md`](runbook-tfstate.md) 3절.

```bash
BUCKET=cntlp-aws-tfstate
REGION=ap-northeast-2

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 전용 KMS 키. Vault auto-unseal 키와 섞지 않는다 — 용도가 다르면 감사 로그의
# 줄도 달라야 한다.
KEY=$(aws kms create-key --description "Terraform state encryption for $BUCKET" \
      --query KeyMetadata.KeyId --output text)
aws kms create-alias --alias-name "alias/$BUCKET" --target-key-id "$KEY"

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration "{
    \"Rules\":[{\"ApplyServerSideEncryptionByDefault\":
      {\"SSEAlgorithm\":\"aws:kms\",\"KMSMasterKeyID\":\"alias/$BUCKET\"},
      \"BucketKeyEnabled\":true}]}"
```

> **버킷 기본 암호화만으로는 부족하다.** 각 스택의 `backend.tf` 가
> `kms_key_id = "alias/cntlp-aws-tfstate"` 를 명시해야 한다. S3 백엔드는 PUT
> 마다 암호화 방식을 요청 헤더에 명시해 보내고, 명시값이 버킷 기본값을 이긴다.
> 빠뜨리면 그 스택의 상태만 조용히 `AES256` 으로 되돌아간다
> → `findings/20260731_tfstate-sse-silent-downgrade.md`

전수 확인:

```bash
aws s3api list-objects-v2 --bucket "$BUCKET" --query 'Contents[].Key' --output text \
| tr '\t' '\n' | while read -r k; do
    printf '%-40s %s\n' "$k" \
      "$(aws s3api head-object --bucket "$BUCKET" --key "$k" \
         --query '[ServerSideEncryption,SSEKMSKeyId]' --output text)"
  done
```

---

## 2. AWS 기반 — network → egress

```bash
terraform -chdir=terraform/aws/network init
terraform -chdir=terraform/aws/network apply

terraform -chdir=terraform/aws/egress init
terraform -chdir=terraform/aws/egress apply     # nat_gateway_id 가 나와야 한다
```

`network` 가 만드는 것 — VPC, 퍼블릭·프라이빗 서브넷, 라우트 테이블, EICE.
`egress` 가 만드는 것 — NAT Gateway.

**둘을 나눈 이유는 비용이다.** NAT 는 월 $35 정도 상시 과금이라 쓰지 않을 때
`egress` 만 destroy 한다. 프라이빗 서브넷 구조를 유지하면서 과금을 끊는 방법이다.

> ⚠️ **`egress` 를 destroy 하기 전에 Vault 를 먼저 내린다.** Vault 는 프라이빗
> 서브넷에 있고 접근 경로가 tailnet 뿐인데, NAT 가 없으면 좌표 서버로 나가지
> 못해 메시에서 떨어진다. **인스턴스는 살아 있는데 아무도 닿을 수 없게 된다.**
> 절차는 [`runbook-vault.md`](runbook-vault.md) 6절.

`network` 는 `terraform.tfvars` 를 요구하고 그 파일은 gitignored 다.
`enable_eice` 와 CIDR 값이 거기 있다. **값을 모른 채 apply 하면 살아 있는
EICE 를 지우려 든다.**

---

## 3. Vault — 서버 → 초기화 → 정책 → 시크릿

여기가 가장 길고, 사람만 할 수 있는 단계가 둘 섞여 있다.
전문은 [`runbook-vault.md`](runbook-vault.md), 설계 근거는
[`vault-architecture.md`](vault-architecture.md).

### 3-1. EC2 를 만든다

```bash
terraform -chdir=terraform/aws/vault init
terraform -chdir=terraform/aws/vault apply
```

15개 자원 — EC2(프라이빗 서브넷, 퍼블릭 IP 없음), KMS 키(auto-unseal),
S3(스냅샷), IAM 인스턴스 프로파일, 보안 그룹.

**보안 그룹 인바운드는 EICE SSH 하나뿐이다.** 메시에 들어가기 전 유일한
접근 수단이 EICE 다.

### 3-2. Vault 를 설치한다

```bash
source scripts/cntlp-env.sh          # 이 시점엔 Vault 가 없어 온프렘 부분은 실패한다
export CNTLP_SSH_PRIVATE_KEY=~/.ssh/cantaloupe_ed25519
export CNTLP_TAILSCALE_AUTH_KEY='tskey-auth-...'    # 손으로. 아직 Vault 가 없다

cd ansible
ansible-playbook -i inventories/aws/aws_ec2.yaml playbooks/site-vault.yaml \
  -e vault_awskms_key_id=$(terraform -chdir=../terraform/aws/vault output -raw vault_kms_key_id)
```

기대 결과 — `seal=awskms`, `initialized=false`.

> `cntlp-env.sh` 는 Vault 가 없으면 온프렘 값 설정에 실패하고 `rc=1` 을 낸다.
> **그래도 AWS 자격증명과 `ANSIBLE_CONFIG` 은 세워진다** — 이 단계가 성립하도록
> 그 순서로 짜여 있다.

### 3-3. 초기화 — 사람만, 한 번만, 되돌릴 수 없다

```bash
export VAULT_ADDR=https://cntlp-aws-vault-01.<tailnet>.ts.net:8200
vault operator init -recovery-shares=5 -recovery-threshold=3
```

**출력이 화면에 한 번만 나온다.** recovery key 5개와 초기 root 토큰을
오프라인 봉투에 넣는다. 자동화하지 않는 이유가 이것이다.

봉투에 넣는 것은 **이 둘뿐이다.** Proxmox 토큰은 Proxmox UI 에서, Tailscale
키는 admin 콘솔에서 재발급된다 — 복구 경로가 이미 있는 것을 봉투에 넣으면
봉투가 관리 부담만 된다.

### 3-4. 정책과 AppRole

```bash
export VAULT_TOKEN='<초기 root 토큰>'
terraform -chdir=terraform/vault init
terraform -chdir=terraform/vault apply
```

10개 자원 — KV v2 mount(`secret/`), 정책 4개, AppRole 2개, 감사 장치(`file/`).

**이 apply 에는 root 토큰이 필요하다.** `pneuma` 정책은 자기 권한을 넓힐 수
없게 만들어져 있어서 정책 변경을 못 한다. 의도된 제약이다.

### 3-5. 계정과 시크릿 — 사람만

```bash
terraform -chdir=terraform/vault output -raw next_steps    # 명령 전문이 나온다
```

순서는 ① `pneuma` userpass 계정 ② AppRole `secret_id` 발급
③ 시크릿 4개 투입 ④ root 토큰 버리고 userpass 로 재로그인 ⑤ 정책 경계 확인.

**시크릿 투입을 terraform 이 하지 않는 이유** — 값이 tfstate 에 평문으로
남는다. 자세한 것은 [`runbook-secrets.md`](runbook-secrets.md).

⑤가 형식적인 절차가 아니다. 이게 이 설계의 유일한 증거다.

```bash
# terraform-onp 토큰으로 개인키를 읽으면 403 이어야 한다
VAULT_TOKEN=$TOKEN vault kv get secret/ssh/cntlp-private
```

### 3-6. root 토큰을 버린다

```bash
unset VAULT_TOKEN
vault login -method=userpass username=pneuma      # TTL 8h
```

**`vault login` 은 `VAULT_TOKEN` 을 export 하지 않는다.** 토큰 헬퍼
(`~/.vault-token`)에 저장할 뿐이고, terraform·ansible·`cntlp-env.sh` 셋 다
그 파일을 읽는다. export 는 필요 없다.

---

## 4. 노드 VM 을 만든다

여기부터 `cntlp-env.sh` 가 온전히 동작한다.

```bash
source scripts/cntlp-env.sh      # rc=0 이어야 한다
```

이게 세우는 것 — Proxmox 토큰 4종(Vault 에서), SSH 개인키(ssh-agent 메모리로,
8h), AWS 자격증명, `ANSIBLE_CONFIG`.

### 순서는 상관없다. 셋은 독립이다.

```bash
terraform -chdir=terraform/aws/compute apply    # 컨트롤플레인 + AWS 워커
terraform -chdir=terraform/gcp     apply        # GCP 워커
terraform -chdir=terraform/onp     apply        # 온프렘 워커 (Proxmox)
```

**`terraform/onp` 만 Vault 를 읽는다.** Proxmox 토큰은 ephemeral 자원이라
tfstate 에 남지 않고, SSH 공개키는 data source 로 읽어 cloud-init 에 들어간다.

각 스택이 붙이는 태그가 그대로 ansible 그룹이 된다.

| 태그 | ansible 그룹 | 쓰는 곳 |
|---|---|---|
| `platform=aws\|gcp\|onp` | `platform_aws` … | 플레이북 hosts |
| `role=control-plane\|service\|devops\|monitoring\|logging` | `role_*` | group_vars, 노드 라벨 |
| `component=vault` | `component_vault` | `site-vault.yaml` |

> Proxmox 태그는 `key=value` 를 못 쓴다. `platform-onp` 처럼 하이픈으로 붙여
> 두고 인벤토리가 접두사를 떼어낸다. **이 블록이 없으면 그룹이 안 생기고
> 플레이북이 `0 hosts matched` 로 조용히 끝난다.**

---

## 5. 클러스터를 세운다

```bash
cd ansible
ansible-inventory --graph                                  # 그룹이 다 보이나
ansible platform_aws:platform_gcp:platform_onp -m ping      # 전부 pong 인가
ansible-playbook playbooks/site-cluster.yaml
```

`site-cluster.yaml` 이 부르는 순서 —

1. `site-prerequisites.yaml` — OS·Tailscale·containerd·kubeadm 패키지
   (`!component_vault` 로 Vault 노드는 뺀다)
2. `site-control-plane.yaml` — `kubeadm init`
3. `site-cni.yaml` — Calico
4. `site-workers.yaml` — `kubeadm join`
5. `site-node-labels.yaml` — `platform`/`role` 라벨 보정

**Tailscale 키를 손으로 export 하지 않는다.** 온프렘은 group_vars 가 Vault 에서
읽고, 이미 가입된 노드는 그 lookup 조차 하지 않는다(jinja 지연 평가).

`ansible-inventory --graph` 를 먼저 돌리는 이유 — 그룹이 비어 있어도 플레이북은
**실패하지 않는다.** `0 hosts matched` 는 성공으로 끝난다. 그래서 실행 전에
눈으로 본다.

### 확인

```bash
ansible-playbook playbooks/site-verify.yaml
kubectl get nodes -L platform,role
```

기대 —

```
NAME              STATUS  ROLES          PLATFORM  ROLE
cntlp-aws-cp-01   Ready   control-plane  aws       control-plane
cntlp-aws-wk-01   Ready   <none>         aws       service
cntlp-gcp-wk-01   Ready   <none>         gcp       monitoring
cntlp-gcp-wk-02   Ready   <none>         gcp       logging
cntlp-onp-wk-01   Ready   <none>         onp       devops
```

---

## 6. 그 위에 얹는 것

```bash
terraform -chdir=terraform/aws/database apply     # RDS. 네트워크만 있으면 언제든
```

RDS 마스터 비밀번호는 **Vault 가 아니라 AWS Secrets Manager** 에 둔다
(`manage_master_user_password = true`). RDS 가 자동 회전하는 이점을 Vault 로
가져오면 잃기 때문이다. 저장소가 둘인 상태를 의도적으로 받아들였다.

ArgoCD 설치와 Root Application 등록은 이 리포 밖이다 → `repos/02-k8s-manifests`.

**이 리포의 ansible 은 애플리케이션을 배포하지 않는다.** 클러스터가 선 뒤의
변경은 ArgoCD 가 가져간다.

---

## 지금 실제로 서 있는 것 (2026-07-31)

| 조각 | 상태 |
|---|---|
| tfstate 버킷 + KMS | 있음. 8개 스택 전부 `kms_key_id` 명시 |
| `aws/network`·`egress` | apply 완료 |
| Vault | 서 있음. 초기화·정책·시크릿 4개 완료 |
| `aws/compute`·`gcp`·`onp` | apply 완료 |
| K8s 클러스터 | **5노드 Ready** (aws 2 / gcp 2 / onp 1), Calico, ArgoCD |
| `aws/database` | 스택 있음 |

남은 것과 막힌 것은 워크스페이스의 `HANDOFF.md` 를 본다.

---

## 순서를 어겼을 때 나오는 증상

전부 **에러가 아니라 이상한 성공**으로 나타난다. 그게 이 문서가 존재하는 이유다.

| 어긴 것 | 증상 |
|---|---|
| `egress` 없이 Vault | apt·tailnet 조인이 타임아웃. `check` 블록이 잡는다 |
| Vault 없이 `terraform/onp` | plan 이 `failed to configure Vault address` 로 죽는다 |
| `cntlp-env.sh` 없이 ansible | `Invalid URL '/api2/json/nodes'` — 원인이 두 단계 앞이다 |
| 그룹이 빈 채로 플레이북 | `0 hosts matched` + **성공 종료** |
| `kms_key_id` 없이 새 스택 | apply 성공. 상태만 조용히 `AES256` |
| ACL 에 없는 태그로 조인 | `tailscale up` 성공. 노드가 뜬 채로 고립 |
