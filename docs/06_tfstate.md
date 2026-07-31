# 06 — tfstate 버킷과 암호화 키

모든 terraform 스택의 상태가 사는 곳. **이 두 자원만 terraform 밖에 있다.**

| 자원 | 이름 | 만든 방법 |
|---|---|---|
| S3 버킷 | `cntlp-aws-tfstate` | AWS CLI (수동) |
| KMS 키 | `alias/cntlp-aws-tfstate` | AWS CLI (수동) |

```
버킷: cntlp-aws-tfstate  (ap-northeast-2, 버저닝 Enabled)
키:   718623c2-4a33-4324-a159-68e22ae161b4
      alias/cntlp-aws-tfstate, 연 1회 자동 회전
```

여덟 스택이 이 버킷의 서로 다른 `key` 를 쓴다 — `aws/network`, `aws/egress`,
`aws/compute`, `aws/database`, `aws/vault`, `vault`, `gcp`, `onp`.

---

## 1. 왜 terraform 이 소유하지 않나

순환이다. 이 버킷과 키가 **모든 스택의 상태를 담고 암호화한다.** 어떤 스택이
이것들을 소유하면 그 스택의 상태 자체가 자기가 만든 자원 안에 들어간다.

- `terraform destroy` 한 번이 다른 모든 스택의 상태를 지운다
- 키를 지우면 자신을 포함해 전부 복호할 수 없다
- 처음 세울 때 상태를 둘 곳이 없다

`terraform/bootstrap/` 스택을 만드는 방법도 있지만, 그 스택의 상태를 어디에
둘 것이냐가 그대로 남는다. 로컬에 두면 이 리포가 없애려는 평문 상태 파일이
하나 생긴다. **그래서 손으로 만들고 여기에 적는다.**

각 스택의 `backend.tf` 가 "버킷은 terraform init 전에 별도로 생성되어 있어야
한다"고 못박은 것이 이 규칙이다.

## 2. 키를 잃으면 상태를 전부 잃는다

**이 키는 삭제하지 않는다.** 지우면 여덟 스택의 상태를 복호할 수 없고,
terraform 은 실제로 살아 있는 자원을 전부 잊는다. 그 뒤에 남는 선택지는
`terraform import` 를 자원 하나하나에 손으로 거는 것뿐이다.

Vault auto-unseal 키(`alias/cntlp-aws-vault-unseal`)와 **다른 키다.** 섞지
않는다 — 용도가 다르면 키도 달라야 CloudTrail 에서 "누가 상태를 복호했나"와
"누가 Vault 를 unseal 했나"가 다른 줄로 남는다.

키가 이미 지워진 뒤라면 삭제 대기 기간(기본 30일) 안에서만 되돌릴 수 있다.

```bash
aws kms cancel-key-deletion --key-id alias/cntlp-aws-tfstate
aws kms enable-key --key-id alias/cntlp-aws-tfstate
```

## 3. 처음부터 다시 세울 때

계정을 갈아엎었거나 다른 계정에 복제할 때.

```bash
BUCKET=cntlp-aws-tfstate
REGION=ap-northeast-2

# 1. 버킷
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# 2. 버저닝. **암호화보다 먼저다.** 상태를 잘못 덮어썼을 때 되돌릴
#    유일한 수단이고, 아래 4절의 재작성도 이것이 있어야 안전하다.
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 3. 키. Vault auto-unseal 키와 섞지 않는다 (2절)
KEY_ID=$(aws kms create-key \
  --description "Terraform state encryption for $BUCKET" \
  --tags TagKey=Name,TagValue="$BUCKET" TagKey=org,TagValue=cntlp \
         TagKey=owner,TagValue=cantaloupe TagKey=managed-by,TagValue=manual \
         TagKey=data-class,TagValue=user-audio TagKey=lifecycle,TagValue=permanent \
         TagKey=platform,TagValue=aws TagKey=component,TagValue=tfstate \
  --query 'KeyMetadata.KeyId' --output text)

aws kms create-alias --alias-name "alias/$BUCKET" --target-key-id "$KEY_ID"
aws kms enable-key-rotation --key-id "$KEY_ID"

# 4. 기본 암호화. BucketKeyEnabled 가 없으면 KMS 요청이 객체 접근마다
#    발생해서 요금이 붙는다.
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration "{
    \"Rules\": [{
      \"ApplyServerSideEncryptionByDefault\": {
        \"SSEAlgorithm\": \"aws:kms\",
        \"KMSMasterKeyID\": \"alias/$BUCKET\"
      },
      \"BucketKeyEnabled\": true
    }]
  }"
```

> **이것만으로는 부족하다.** 각 스택의 `backend.tf` 에 `kms_key_id` 도 있어야
> 한다 → [5절](#5-backendtf-에-kms_key_id-가-없으면-전부-되돌아간다)

`managed-by = manual` 이 다른 자원과 다른 유일한 태그다. 1절의 이유를 태그에
남긴 것이다 — 태그만 보고 "terraform 이 빠뜨렸나" 하고 찾아 헤매지 않도록.

## 4. 기본 암호화를 바꾼 뒤 기존 객체를 옮긴다

**`put-bucket-encryption` 은 새 객체에만 적용된다.** 이미 있는 상태 파일은
옛 암호화 그대로 남는다. 확인 없이 넘어가면 "버킷은 aws:kms 인데 정작 상태는
AES256" 인 채로 몇 달이 간다.

> **2026-07-31 정정.** 이 문단은 한때 "다음 `apply` 로 그 스택이 다시 쓰일
> 때까지 바뀌지 않는다" 고 적혀 있었다. **틀렸다. 다음 apply 가 오히려
> 되돌린다.** 아래 5절이 이유이고, 제자리 복사만으로는 고쳐지지 않는다.

무엇이 어떻게 암호화돼 있는지 먼저 전수로 본다.

```bash
BUCKET=cntlp-aws-tfstate

aws s3api list-objects-v2 --bucket "$BUCKET" --query 'Contents[].Key' --output text \
| tr '\t' '\n' | while read -r k; do
    printf '%-40s %s\n' "$k" \
      "$(aws s3api head-object --bucket "$BUCKET" --key "$k" \
         --query '[ServerSideEncryption,SSEKMSKeyId]' --output text)"
  done
```

옮기는 것은 제자리 복사다. 버저닝이 켜져 있으므로 이전 버전이 남는다.

```bash
aws s3api copy-object --bucket "$BUCKET" --key "$KEY" \
  --copy-source "$BUCKET/$KEY" \
  --server-side-encryption aws:kms \
  --ssekms-key-id "alias/$BUCKET" \
  --bucket-key-enabled \
  --metadata-directive COPY
```

**terraform 이 돌고 있지 않을 때 한다.** 상태를 밖에서 덮어쓰는 일이라 apply
중이면 경합한다.

끝나면 아무 스택에서나 `terraform plan` 이 `No changes` 로 끝나는지 본다.
읽기와 락 쓰기가 둘 다 되는지 확인하는 가장 싼 방법이다.

### 옛 버전은 옛 암호화로 남는다

제자리 복사는 새 버전을 만들 뿐이고 이전 버전은 그대로다. 버킷 기본 암호화가
`aws:kms` 라는 사실과 별개로, 버저닝 히스토리에는 SSE-S3 로 암호화된 옛
상태가 남아 있다. 지우려면 lifecycle 규칙으로 noncurrent 버전을 만료시킨다 —
다만 그것은 되돌릴 수단을 버리는 것이기도 하다. **지금은 두기로 했다.**

## 5. `backend.tf` 에 `kms_key_id` 가 없으면 전부 되돌아간다

**버킷 기본 암호화만으로는 부족하다.** 이것이 4절을 무력화하는 지점이고,
2026-07-31 에 실제로 그 상태였다.

S3 백엔드는 상태를 PUT 할 때 **암호화 방식을 요청 헤더에 명시해서** 보낸다.
`encrypt = true` 만 주면 그 헤더는 `AES256`(SSE-S3) 이다. 명시값은 버킷
기본값을 이기므로, 버킷이 `aws:kms` 여도 terraform 이 쓸 때마다 객체가
SSE-S3 로 되돌아간다. 4절의 제자리 복사는 그때까지만 유효하다.

```hcl
terraform {
  backend "s3" {
    ...
    encrypt    = true
    kms_key_id = "alias/cntlp-aws-tfstate"   # 이 줄이 없으면 AES256 이다
  }
}
```

**조용히 일어난다.** apply 는 성공하고, 버킷 설정을 봐도 `aws:kms` 이고,
객체를 하나하나 `head-object` 로 봐야만 드러난다. 발견 당시 여섯 스택 중
셋이 이미 되돌아가 있었다 → `findings/20260731_tfstate-sse-silent-downgrade.md`

고친 뒤에는 백엔드 설정이 바뀐 것이므로 재초기화가 필요하다.

```bash
terraform -chdir=terraform/<스택> init -reconfigure
```

> 디렉터리에 옛 로컬 `terraform.tfstate` 가 남아 있으면 `-reconfigure` 가
> "상태를 옮길까" 를 물으며 멈춘다. **S3 쪽이 최신인지 먼저 확인하고** 로컬
> 사본을 치운 뒤 다시 돌린다.

확인은 4절의 전수 조회와 같다. **전부 `aws:kms` 여야 한다.**

## 6. 버킷이 하나인 이유

한때 둘이었다.

| 스택 | 옛 버킷 |
|---|---|
| `terraform/aws/{network,egress,compute,database}` | `cntlp-aws-tfstate` |
| `terraform/{gcp,onp}` | `cntlp-tfstate` |

**`cntlp-tfstate` 는 만들어진 적이 없다** (2026-07-31 확인, `NoSuchBucket`).
그래서 `terraform/onp` 는 `backend_override.tf` 로 로컬 상태를 쓰고 있었다.
"AWS 가 준비되면 마이그레이션" 이라는 메모의 진짜 내용이 이것이다.
**2026-07-31 에 S3 로 옮기고 그 파일을 지웠다.**

온프렘·GCP 상태가 `aws` 이름의 버킷에 들어가는 것이 어색해 보이지만 맞다.
명명 규약의 물리 위치 토큰은 **그 자원이 어디에 사는지**를 가리키고, 버킷
자체는 AWS 자원이다. 안에 무엇이 담겼는지는 `key` 가 가른다 —
`onp/`, `gcp/`, `aws/vault/`.

## 7. 남은 것

- **키 정책이 기본값이다.** 계정 root 에 전권을 주고 나머지는 IAM 에
  위임한다. 주체가 워크스테이션 하나뿐인 지금은 이걸로 충분하다. CI 나 다른
  사람이 붙으면 그때 `kms:Decrypt` 를 주체별로 갈라 키 정책에 박는다
- **버킷에 태그가 없다.** 다른 자원은 전부 붙어 있다
