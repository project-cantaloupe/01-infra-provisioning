output "packer_instance_profile_name" {
  description = "Instance Profile used by the temporary Packer builder"
  value       = aws_iam_instance_profile.packer.name
}

output "packer_security_group_id" {
  description = "Outbound-only Security Group used by the temporary Packer builder"
  value       = aws_security_group.packer.id
}

output "packer_subnet_id" {
  description = "Private Subnet used by the temporary Packer builder"
  value       = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
}
