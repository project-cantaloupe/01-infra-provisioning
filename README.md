# infra-provisioning

서버와 클러스터를 만드는 코드. **사람이 직접 실행한다.** ArgoCD가 보지 않는다.

## 실행 순서

```bash
# 1. VM 을 만든다
terraform -chdir=terraform/aws    apply
terraform -chdir=terraform/gcp    apply
terraform -chdir=terraform/onprem apply

# 2. K8s 를 올린다 (인벤토리는 자동으로 채워진다)
ansible-playbook playbooks/site-control-plane.yaml
ansible-playbook playbooks/site-workers.yaml

# 3. ArgoCD 를 심는다 (이후는 ArgoCD 가 맡는다)
ansible-playbook playbooks/bootstrap-argocd.yaml
```

3번 이후로는 클러스터 변경을 여기서 하지 않는다. `k8s-manifests` 로 간다.

> **위 순서는 아직 전부 성립하지 않는다.** `site-control-plane.yaml` 과
> `bootstrap-argocd.yaml` 은 파일이 없다. 지금 있는 것은 `site-workers.yaml`
> 하나다 (→ `tasks/todo/002_bootstrap-blockers.md` 5번).

## 런북

| 문서 | 언제 |
|---|---|
| [docs/runbook-onprem-vm-recreate.md](docs/runbook-onprem-vm-recreate.md) | 온프렘 워커 VM을 지우고 다시 만들어 재조인할 때. 무엇이 멱등이고 무엇이 사람 손을 요구하는지 |
| [terraform/onprem/README.md](terraform/onprem/README.md) | Proxmox 사전 설정(API 토큰, snippets 콘텐츠 타입) |

## 구조

```
terraform/
  modules/finops-tags/       모든 자원에 붙일 비용 태그
  modules/secops-baseline/   공통 IAM·보안그룹
  aws/     컨트롤 플레인 + 워커 + LB
  gcp/     워커
  onprem/  Proxmox VM
ansible/
  inventories/   동적 인벤토리 (손으로 IP 를 적지 않는다)
  roles/         OS 설정, K8s 설치, VPN
  playbooks/     실행 진입점
```

## 인벤토리에 IP 를 적지 않는다

`hosts.ini` 를 만들지 마라. Terraform 이 VM 을 다시 만들면 IP 가 바뀌는데
파일은 그대로 남아 반드시 어긋난다.

대신 Terraform 이 붙인 태그를 Ansible 이 읽어 그룹을 만든다.

| 태그 | 값 |
|---|---|
| `Area` | `aws` / `gcp` / `onprem` |
| `Role` | `control-plane` / `worker` |

## Terraform 상태는 S3 에 둔다

온프렘 서버가 죽었을 때 그 서버를 복구하는 데 필요한 상태가 그 서버 안에 있으면
곤란하다. 세 스택 모두 같은 S3 버킷을 쓴다.

## 클러스터 안쪽 거버넌스는 여기 없다

파드 보안이나 리소스 쿼터는 [`k8s-manifests/governance/`](../k8s-manifests/) 에 있다.
여기는 클라우드 자원(태그, IAM, 보안그룹) 쪽만 담당한다.
