# FinOps 인프라 계약

## 범위

이 저장소는 OpenCost·Prometheus·Grafana·VPA를 배포하지 않는다. 대신
`02-k8s-manifests`의 수집·계산 계층이 필요로 하는 다음 입력을 만든다.

- 클라우드·On-prem VM의 안정적인 신원과 사이징 메타데이터
- Kubernetes Node 라벨과 `spec.providerID`
- Provider recommendation과 S3 수집에 필요한 최소 read-only 권한
- Audio S3 Versioning·Lifecycle·Storage Class 정책
- Metrics Server가 우회 없이 검증할 kubelet serving certificate

## Node 메타데이터 계약

모든 Node는 다음 라벨을 가져야 한다.

| 라벨 | 용도 |
| --- | --- |
| `platform=aws|gcp|onp` | 플랫폼 분류·대시보드 필터·가격 검증 |
| `role` | 배치 경계와 비용 분류 |
| `topology.kubernetes.io/region` | OpenCost CSV 가격 매칭의 첫 번째 키 |
| `node.kubernetes.io/instance-type` | OpenCost CSV 가격 매칭의 두 번째 키 |

AWS·GCP Node의 `spec.providerID`는 Provider collector가 Project/Zone/Instance
또는 EC2 Instance를 특정하는 신원이다. 가격 매칭 키로 대체하지
않는다. On-prem은 `region=on-premise`와
`instance-type=custom-<vCPU>vcpu-<GiB>gib`를 사용하며 providerID 검사
대상에서 제외한다. 다만 VM과 Node 대응 검증을 위한 팀 로컬
`custom:///node-name` providerID는 Ansible Node 계약으로 유지한다.

Terraform/Provider 태그는 Ansible 동적 인벤토리의 입력이고, kubeadm
역할이 이를 Node 라벨로 적용한다. 두 계층의 표기를 같은 것으로
간주하지 말고 `site-verify.yaml`과 다음 명령으로 최종 Node를 확인한다.

```bash
kubectl get nodes \
  -L platform,role,topology.kubernetes.io/region,node.kubernetes.io/instance-type \
  -o custom-columns=NAME:.metadata.name,PROVIDER:.spec.providerID
```

새 region/instance type은 즉시 OpenCost가 임의 가격을 만들지 않는다.
`02-k8s-manifests/platform/gcp/opencost/pricing-catalog.yaml`에 검증된 가격을
등록하고 generated CSV/checksum/coverage 검증을 통과해야 한다.

## Provider recommendation IAM

Collector는 Kubernetes에 장기 Cloud key를 저장하지 않는다.

- GCP collector는 `platform=gcp,role=monitoring` VM의 Metadata Service 단기
  token으로 Machine Type recommendation을 읽는다.
- AWS collector는 `role=service` EC2의 IMDSv2와
  `cntlp-aws-worker-node` Instance Profile을 사용한다. 권한은
  `compute-optimizer:GetEnrollmentStatus`,
  `compute-optimizer:GetEC2InstanceRecommendations`,
  `ec2:DescribeInstanceTypes`의 읽기 범위이다.

이 권한은 추천 수집용이며 VM resize, terminate, Pod request 변경을
허용하지 않는다. AWS collector는 콘솔과 같은 ARM64 추천을 받기 위해
`AWS_ARM64` preference를 명시하므로 권한과 인스턴스 타입 질의를
일반 AMD64 가정으로 바꾸지 않는다.

## Audio S3 비용 계약

Terraform Audio stack은 지정된 `cntlp-aws-quarantine`와
`cntlp-aws-transcode` bucket을 소유한다. 둘 다 Versioning을 켜고 이전
버전을 7일 후 만료시킨다.

- Quarantine의 `incoming/` prefix에 있는 128KiB 초과 현재 객체:
  30일에 Standard-IA, 60일에 Glacier Instant Retrieval
- Quarantine 현재 객체: 자동 만료 없음
- Transcode 현재 객체: Storage Class 전환·자동 만료 없음
- 두 bucket의 noncurrent version: 7일 후 만료

S3 FinOps collector는 이 두 bucket을 명시적으로 수집하며 AWS 계정의 모든
bucket을 자동 발견하지 않는다. 대시보드의 Current 용량·Storage
Class 추이는 6시간 수집 주기이며, noncurrent version 용량도 포함한
전체 과금 용량과 구분해 해석한다.

## Metrics Server·VPA TLS 계약

VPA Recommender의 최신 사용량 입력은 Metrics Server의
`metrics.k8s.io`이다. 모든 kubelet 10250 serving certificate는 Kubernetes
CA가 서명하고 노드 DNS/IP SAN과 일치해야 한다.
`--kubelet-insecure-tls`를 추가하거나 APIService의 TLS 검증을 끄는 방식으로
해결하지 않는다. 전환 절차는 `runbook-kubelet-serving-tls.md`를 따른다.

VPA Recommender, VPA object, collector, Prometheus 보조 신호는
`02-k8s-manifests`의 책임이다. 이 저장소의 VM 사이즈나 Terraform
resource request를 VPA Target에서 자동 역산하지 않는다.

## 변경 완료 기준

1. Terraform/Ansible 검증과 동적 인벤토리 결과가 성공한다.
2. Node 라벨과 providerID가 실제 Provider/Proxmox 자원과 일치한다.
3. Metrics Server와 VPA의 상태가 정상이고 insecure TLS flag가 없다.
4. OpenCost에 Node 가격 메트릭이 있고 catalog coverage/불일치 경고가 없다.
5. Provider/S3 collector의 최신성과 수집 성공 메트릭을 확인한다.
6. 대시보드 Run-rate·Idle·potential savings를 실제 청구·확정
   절감으로 기록하지 않는다.
