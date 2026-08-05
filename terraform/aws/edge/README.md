# AWS Audio Edge

Public NLB와 Istio ingress gateway 사이의 AWS 자원을 관리한다.

## 생성 자원

- internet-facing Network Load Balancer
- NLB Security Group과 Worker NodePort ingress 규칙
- TCP 80, 443 listener
- Istio Gateway NodePort용 Target Group
- AWS Worker Target 등록
- 선택형 Route53 Alias Record
- 선택형 cert-manager DNS-01 IAM Role

TLS는 NLB가 아니라 Istio Gateway에서 종료한다. HTTP listener는 Istio가 HTTPS로
전환할 수 있도록 TCP 80을 그대로 전달한다.

## 사전 조건

1. 기존 Network 상태와 Worker Security Group 확인
2. Compute 상태 적용과 AWS Worker 1대 이상 생성
3. NLB 적용 전 Istio ingress gateway의 NodePort 계약 확인

```text
HTTP    30080
HTTPS   30443
Health  32021 -> /healthz/ready
```

## 검증 순서

```bash
cp terraform/aws/edge/terraform.tfvars.example terraform/aws/edge/terraform.tfvars
# terraform.tfvars의 AWS 계정 ID와 관리 태그 값을 실제 값으로 교체

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
