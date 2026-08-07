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

output "boot_test_instance_id" {
  description = "Temporary Golden AMI Boot Test instance ID, or null when disabled"
  value       = var.enable_boot_test ? aws_instance.boot_test[0].id : null
}

output "boot_test_ami_id" {
  description = "Golden AMI ID selected for the temporary Boot Test, or null when disabled"
  value       = var.enable_boot_test ? data.aws_ami.boot_test[0].id : null
}

output "bootstrap_secret_name" {
  description = "Temporary bootstrap Secret name whose value must be inserted outside Terraform, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.worker_bootstrap[0].name : null
}

output "bootstrap_secret_arn" {
  description = "Temporary bootstrap Secret ARN allowed by the Worker Role, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.worker_bootstrap[0].arn : null
}
