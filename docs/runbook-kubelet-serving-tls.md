# Kubelet Serving TLS 전환 Runbook

Metrics Server가 각 노드의 kubelet HTTPS(10250)를 검증하도록 self-signed
serving certificate를 Kubernetes CA가 서명한 인증서로 전환한다. 기존 Pod,
etcd, kubeconfig, kubelet client certificate는 변경하지 않는다.

## 안전 원칙

- 한 번에 노드 한 대만 작업한다.
- Control Plane은 마지막에 작업한다.
- `kubernetes.io/kubelet-serving` CSR을 자동 승인하지 않는다.
- 요청자·CN·Organization·SAN이 실제 노드와 일치할 때만 승인한다.
- 노드가 Ready로 복귀하지 않으면 다음 노드로 넘어가지 않는다.
- Metrics Server에 `--kubelet-insecure-tls`를 사용하지 않는다.

## 1. 작업 전 상태 저장

Control Plane에서 실행한다.

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get csr
```

모든 노드가 `Ready`인지 확인한다. 장애 중인 노드가 있으면 먼저 복구한다.

기존 클러스터의 `kubelet-config` ConfigMap에도 아래 값을 추가한다. 이 변경은
현재 실행 중인 kubelet을 즉시 재시작하지 않지만, 이후 join/reconfigure되는
노드가 같은 설정을 받게 한다.

```bash
kubectl -n kube-system edit configmap kubelet-config
```

`data.kubelet` YAML 안의 `kind: KubeletConfiguration` 바로 아래에 추가한다.

```yaml
serverTLSBootstrap: true
```

편집 후 다음 명령으로 값이 저장됐는지 확인한다.

```bash
kubectl -n kube-system get configmap kubelet-config \
  -o jsonpath='{.data.kubelet}' | grep '^serverTLSBootstrap: true$'
```

## 2. 노드 한 대 적용

AWS, GCP, On-Prem 인벤토리를 평소와 동일하게 함께 지정하되 `--limit`에는
정확히 한 노드명만 쓴다. 플레이북 자체도 한 대가 아니면 중단한다.

```bash
cd ansible
ansible-playbook \
  -i inventories/aws/aws_ec2.yaml \
  -i inventories/gcp/gcp_compute.yaml \
  -i inventories/onp/proxmox.yaml \
  playbooks/site-kubelet-serving-tls.yaml \
  --limit cntlp-aws-wk-01
```

플레이북은 설정 파일을 backup하고 해당 노드의 kubelet만 재시작한다. 기존
containerd 컨테이너는 삭제하지 않는다.

## 3. CSR 내용 검증과 승인

Pending serving CSR을 찾는다.

```bash
kubectl get csr \
  -o custom-columns=NAME:.metadata.name,SIGNER:.spec.signerName,REQUESTOR:.spec.username,CONDITION:.status.conditions[*].type
```

대상 CSR의 요청 내용을 디코딩한다.

```bash
CSR=<pending-csr-name>
kubectl get csr "$CSR" -o jsonpath='{.spec.request}' \
  | base64 -d \
  | openssl req -noout -text
```

다섯 조건을 모두 확인한다.

1. signerName이 `kubernetes.io/kubelet-serving`
2. requestor가 `system:node:<실제 노드명>`
3. CN이 `system:node:<실제 노드명>`
4. Organization이 `system:nodes`
5. DNS/IP SAN이 그 노드의 실제 hostname과 Tailscale node IP

일치하면 승인한다. 하나라도 다르면 승인하지 말고 deny한다.

```bash
kubectl certificate approve "$CSR"
# 불일치 시: kubectl certificate deny "$CSR"
```

## 4. 노드와 인증서 검증

```bash
kubectl wait --for=condition=Ready node/cntlp-aws-wk-01 --timeout=120s
kubectl get csr "$CSR"
```

대상 노드에서 새 인증서를 확인한다.

```bash
sudo openssl x509 \
  -in /var/lib/kubelet/pki/kubelet-server-current.pem \
  -noout -issuer -subject -dates -ext subjectAltName
```

issuer가 Kubernetes CA이고 SAN이 실제 노드 주소와 일치해야 한다. 확인 후에만
다음 worker 노드로 넘어간다. Control Plane은 모든 worker가 끝난 뒤 마지막에
같은 절차로 작업한다.

## 5. 실패 시 중단과 복구

kubelet이 복귀하지 않으면 다음 노드에 실행하지 않는다. 플레이북이 출력한
`/var/lib/kubelet/config.yaml` backup 파일에서 원본을 복구하고 kubelet을
재시작한다.

```bash
sudo cp /var/lib/kubelet/config.yaml.<backup-timestamp> /var/lib/kubelet/config.yaml
sudo systemctl restart kubelet
sudo systemctl status kubelet --no-pager
```

인증서가 발급되지 않으면 설정을 되돌리기 전에 CSR의 signer, 승인 상태와
kube-controller-manager 로그를 확인한다. 기존 self-signed 인증서를 삭제하지
않았으므로 승인 대기만으로 클러스터 데이터가 사라지지는 않는다.
