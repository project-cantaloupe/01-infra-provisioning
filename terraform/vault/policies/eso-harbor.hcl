# Harbor 네임스페이스의 External Secrets Operator 가 읽을 수 있는 경로
path "secret/data/onp/harbor/*" {
  capabilities = ["read"]
}
path "secret/metadata/onp/harbor/*" {
  capabilities = ["read", "list"]
}
