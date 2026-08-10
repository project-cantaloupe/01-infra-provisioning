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

output "tailscale_oauth_secret_name" {
  description = "Tailscale OAuth Secret name whose value must be inserted outside Terraform, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.tailscale_oauth[0].name : null
}

output "tailscale_oauth_secret_arn" {
  description = "Tailscale OAuth Secret ARN allowed by the Worker Role, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.tailscale_oauth[0].arn : null
}

output "kubeadm_join_secret_name" {
  description = "Rotated kubeadm join Secret name, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.kubeadm_join[0].name : null
}

output "kubeadm_join_secret_arn" {
  description = "Rotated kubeadm join Secret ARN allowed by the Worker Role, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_secretsmanager_secret.kubeadm_join[0].arn : null
}

output "kubernetes_cluster_name" {
  description = "Self-managed Kubernetes cluster name configured for Karpenter"
  value       = local.kubernetes_cluster_name
}

output "worker_instance_profile_name" {
  description = "Existing Worker Instance Profile selected for Karpenter nodes, or null when disabled"
  value       = local.needs_compute_state ? local.worker_instance_profile_name : null
}

output "controller_policy_name" {
  description = "Inline Karpenter controller policy attached to the Control Plane role, or null when disabled"
  value       = var.enable_controller_foundation ? aws_iam_role_policy.karpenter_controller[0].name : null
}

output "kubeadm_rotator_policy_name" {
  description = "Inline kubeadm token rotator policy attached to the Control Plane role, or null when disabled"
  value       = var.enable_bootstrap_foundation ? aws_iam_role_policy.kubeadm_token_rotator[0].name : null
}
