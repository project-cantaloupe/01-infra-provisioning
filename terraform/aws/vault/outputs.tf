output "vault_instance_id" {
  description = "EC2 instance ID; also the Ansible inventory hostname (EICE tunnels target instance IDs)"
  value       = aws_instance.vault.id
}

output "vault_node_name" {
  description = "EC2 Name tag and the hostname Vault registers in the tailnet"
  value       = local.vault_name
}

# Ansible vault-server 롤의 vault_awskms_key_id 로 넘긴다.
#   -e vault_awskms_key_id=$(terraform -chdir=terraform/aws/vault output -raw vault_kms_key_id)
output "vault_kms_key_id" {
  description = "KMS key ID consumed by the Vault awskms seal stanza"
  value       = aws_kms_key.unseal.key_id
}

output "vault_snapshot_bucket" {
  description = "S3 bucket for raft snapshots"
  value       = aws_s3_bucket.snapshots.id
}

output "vault_security_group_id" {
  description = "Vault node security group ID"
  value       = aws_security_group.vault.id
}

# Private IP도 Public IP도 출력하지 않는다.
# Public IP는 애초에 없고, Private IP로는 메시 밖에서 닿지 않는다.
# 출력하면 누군가 그것으로 붙으려다 Security Group에 ingress를 열게 된다.
# 접근은 EICE(SSH) 또는 tailnet(API) 둘뿐이다.
