# AWS Audio Data Path

오디오 업로드, 검사, 비동기 변환, 비공개 재생에 필요한 AWS 관리형 자원을 독립
Terraform 상태로 관리한다. 애플리케이션과 Kubernetes manifest는 이 Stack의
Output을 입력 계약으로 사용한다.

## 생성 자원

기본 구성은 다음 자원을 만든다.

- 원본 격리 S3 버킷 `cntlp-aws-quarantine`
- MP3·waveform 결과 S3 버킷 `cntlp-aws-transcode`
- `scan-result`, `transcode`, `transcode-result` SQS Queue와 Queue별 DLQ
- S3 공개 접근 차단, SSE-S3 암호화, Versioning, Lifecycle
- Presigned PUT과 CloudFront 응답에 필요한 CORS 정책

다음 구성은 비용 또는 외부 선행 조건이 있어 기본값이 비활성화되어 있다.

- CloudFront OAC, Trusted Key Group, Signed URL용 공개키와 Secret 컨테이너
- Self-managed Kubernetes Service Account OIDC 기반 워크로드 IAM Role

## 데이터 흐름

```text
Web -> Presigned PUT -> cntlp-aws-quarantine
                        -> audio-api 업로드 검증·스캔 상태 태그
                        -> scan-result Queue
                        -> audio-events DB 갱신·Outbox 발행
                        -> transcode Queue
                        -> audio-transcode
                        -> cntlp-aws-transcode + transcode-result Queue
                        -> audio-events DB 갱신

Web <- CloudFront Signed URL <- audio-api
    <- CloudFront OAC <- cntlp-aws-transcode
```

`scan-result` 메시지는 `03-app-audio/shared/schema/scan-result.json` 계약을
따른다. `NO_THREATS_FOUND` 태그가 붙은 정확한 S3 Version만 Worker가 읽는 규칙은
검사기 종류와 무관하게 유지된다.

## 단계별 검증

```bash
export AWS_PROFILE=cntlp

cp terraform/aws/audio/terraform.tfvars.example \
  terraform/aws/audio/terraform.tfvars
# 실제 계정 ID, Web Origin, 태그 값을 입력한다.

terraform -chdir=terraform/aws/audio init -reconfigure
terraform -chdir=terraform/aws/audio fmt -check
terraform -chdir=terraform/aws/audio validate
terraform -chdir=terraform/aws/audio test
terraform -chdir=terraform/aws/audio plan
```

첫 plan에서는 CloudFront와 Workload IAM을 비활성화한 채 S3와 SQS만 확인한다.
그 다음 필요한 기능을 하나씩 활성화해 교체 범위와 비용을 분리한다.

## 악성코드 검사 단계

이 Stack은 악성코드 검사기를 포함하지 않는다. 원래 GuardDuty Malware Protection
for S3와 EventBridge 변환으로 설계했으나, 대상 AWS 계정이 Free account plan이라
GuardDuty를 구독할 수 없어 채택하지 않았다.

```text
SubscriptionRequiredException: The AWS Access Key Id needs a subscription for the service
```

해당 Terraform 코드는 비활성 상태로 남겨두지 않고 삭제했다. 계정 플랜이 바뀌어
다시 필요해지면 git 이력에서 복원한다.

대신 `audio-api`가 `/complete` 처리에서 업로드를 검증한 뒤 원본 객체에
`CntlpScanStatus=NO_THREATS_FOUND` 태그를 기록하고 `scan-result`
메시지를 직접 발행한다. **이는 실제 악성코드 검사가 아니라 계약을 유지하기 위한
대체 경로다.** 운영 환경에서 실제 검사가 필요하면 검사기를 이 지점에 끼워 넣는다.

격리 버킷, `scan-result` 계약, 상태 기계, Worker의 태그·checksum 재검증은 그대로
유지된다. 따라서 검사기를 교체해도 `audio-events`와 `audio-transcode`는 수정할
필요가 없다.

`enable_workload_iam`을 켜면 API Role에 `s3:PutObjectTagging`과 `scan-result`
Queue `sqs:SendMessage` 권한이 함께 부여된다.

## CloudFront Signed URL 활성화

개인키를 Git과 Terraform state에 넣지 않도록 로컬에서 Key Pair를 만든다.

```bash
umask 077
openssl genpkey -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out terraform/aws/audio/cloudfront-private-key.pem

openssl pkey \
  -in terraform/aws/audio/cloudfront-private-key.pem \
  -pubout \
  -out terraform/aws/audio/cloudfront-public-key.pub
```

`.pem`과 `.key`는 Git에서 제외된다. 공개키도 환경별로 교체할 수 있도록 실제
운영 파일은 커밋하지 않는다.

```hcl
enable_cloudfront          = true
cloudfront_public_key_path = "cloudfront-public-key.pub"
```

apply 후 Terraform이 만든 Secret 컨테이너에 개인키 값을 별도로 등록한다.

```bash
SECRET_ARN=$(terraform -chdir=terraform/aws/audio \
  output -raw cloudfront_private_key_secret_arn)

AWS_PROFILE=cntlp aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ARN" \
  --secret-string file://terraform/aws/audio/cloudfront-private-key.pem
```

Terraform은 Secret 값이나 개인키를 읽지 않는다. Kubernetes 단계에서는
External Secrets 또는 CSI로 Secret을 파일에 마운트하고, API에 다음 Output을
전달한다.

```text
PLAYBACK_URL_MODE=cloudfront
CLOUDFRONT_BASE_URL
CLOUDFRONT_KEY_PAIR_ID
CLOUDFRONT_PRIVATE_KEY_FILE
```

## Workload IAM 활성화

Self-managed Kubernetes의 Service Account Issuer를 IAM OIDC Provider로 등록한
후에만 활성화한다.

```hcl
enable_workload_iam       = true
cluster_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/..."
cluster_oidc_issuer_url   = "https://..."
```

이 구성을 활성화하면 장기 Access Key나 Worker 공용 Role 대신 `audio-api`,
`audio-events`, `audio-transcode` ServiceAccount마다 S3·SQS·Secrets Manager의
최소 권한을 분리한다. 현재 Self-managed Kubernetes OIDC가 준비되지 않은 상태의
Node Instance Profile 대체안은 이 Foundation에 포함하지 않고 별도 변경으로
권한 노출과 IMDS 차단 경계를 함께 검토한다.

## 비용과 삭제 경계

- S3 저장량, Versioning된 이전 객체, 요청과 데이터 전송
- SQS 요청과 DLQ 보관량
- CloudFront 요청과 전송량
- Secrets Manager Secret 보관

128 KB 초과 원본은 0~29일 Standard, 30~59일 Standard-IA, 60일 이후 Glacier
Instant Retrieval을 기준선으로 둔다. 현재 원본은 자동 삭제하지 않고 이전 버전만
7일 뒤 정리한다. 결과 객체도 현재 버전은 자동 삭제하지 않고 이전 버전만 7일 뒤
정리한다.

Audio 상태만 destroy하면 VPC, EC2, RDS, NLB, Kubernetes Node 등 다른 Stack이
소유한 자원은 유지된다.
버킷은 `force_destroy`를 사용하지 않으므로 객체가 남아 있으면 destroy가 중단된다.
삭제 전 보관 여부를 결정하고 Version까지 비워야 한다. CloudFront 삭제는 전역
배포 해제 때문에 시간이 걸릴 수 있고, Secret은 7일 복구 대기 상태로 전환된다.

전체 삭제 순서는 Audio -> Edge -> Database -> Compute -> Egress -> Network로
진행한다.
