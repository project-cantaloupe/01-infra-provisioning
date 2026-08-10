# AWS Audio Edge

Public NLB와 Istio ingress gateway 사이의 AWS 자원을 관리한다.

## 생성 자원

- internet-facing Network Load Balancer
- NLB Security Group과 Worker NodePort ingress 규칙
- TCP 80 listener
- Istio Gateway NodePort용 Target Group
- AWS Worker Target 등록
- 선택형 ACM 인증서와 Route53 Alias Record
- 선택형 cert-manager DNS-01 IAM Role

현재 TLS는 ACM 인증서를 사용하는 NLB에서 종료하고, VPC 내부의 Istio Gateway
HTTP NodePort로 전달한다.

## 공개 범위

`allowed_ingress_cidrs`에 나열한 Source만 NLB에 도달한다. 기본값이 없으므로
값을 넣지 않으면 apply가 실패한다.

audio-api는 `AUTH_MODE=development` 상태이므로 `0.0.0.0/0`은 기본적으로
거부한다. `apps/audio`의 공개 조회 정책이 먼저 배포되어 아래 경계를 보장할 때만
`public_read_only_access = true`와 전체 공개 CIDR을 함께 사용한다.

- Gateway에서 외부 `X-Cantaloupe-Subject` 제거
- Gateway에서 `GET`·`HEAD`만 허용
- 공개 카탈로그와 공개 음원 상세·재생만 외부 제공

업로드·완료 처리·공개 범위 변경은 Keycloak OIDC 검증 전까지 외부에서 차단한다.

## TLS 종료 경계

Self-managed Kubernetes에 IAM OIDC Provider가 없어 cert-manager DNS-01용 Pod IAM을
사용하지 않는다. ACM은 클러스터 외부에서 인증서를 발급하고 자동 갱신하므로 현재
구성에서는 NLB가 443 TLS Listener를 소유한다. NLB와 Worker 사이는 Security
Group으로 제한된 VPC 내부 HTTP 구간이다.

## 사전 조건

1. 기존 Network 상태와 Worker Security Group 확인
2. Compute 상태 적용과 AWS Worker 1대 이상 생성
3. NLB 적용 전 Istio ingress gateway의 NodePort 계약 확인

```text
HTTP    30080
Health  32021 -> /healthz/ready
```

## 검증 순서

```bash
cp terraform/aws/edge/terraform.tfvars.example terraform/aws/edge/terraform.tfvars
# terraform.tfvars의 AWS 계정 ID와 관리 태그 값을 실제 값으로 교체
# 공개 조회 정책이 없으면 allowed_ingress_cidrs를 접속 단말의 /32로 교체한다
curl -s https://checkip.amazonaws.com

terraform -chdir=terraform/aws/edge init -reconfigure
terraform -chdir=terraform/aws/edge fmt -check
terraform -chdir=terraform/aws/edge validate
terraform -chdir=terraform/aws/edge test
terraform -chdir=terraform/aws/edge plan
```

`plan`에서 NLB 시간당 요금과 LCU, 인터넷 전송 비용 발생 가능성을 확인한 뒤
apply한다.

## 생성과 삭제 경계

```bash
terraform -chdir=terraform/aws/edge apply
terraform -chdir=terraform/aws/edge destroy
```

Edge 상태만 destroy하면 EC2, VPC, RDS, Kubernetes Node는 유지된다. 전체 삭제는
Edge -> Database -> Compute -> Egress -> Network 역순으로 진행한다.

## DNS와 인증서

NLB만 검증할 때는 `create_dns_record = false`를 유지한다. Route53 Public Hosted
Zone과 서비스 주소가 확정되면 `route53_zone_id`, `public_host`를 함께 입력한다.

cert-manager IAM은 self-managed Kubernetes의 Service Account Issuer가 AWS IAM
OIDC Provider로 등록된 뒤에만 활성화한다. OIDC 없이 Worker Instance Profile이나
장기 Access Key를 cert-manager에 공유하지 않는다.
