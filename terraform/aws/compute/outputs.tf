# 아래 output은 S3 Compute state에 저장되며 운영 확인과
# 이후 Ansible/Kubernetes 설정에서 사용할 수 있다.
output "control_plane_private_ip" {
  description = "Private IP used for cluster-internal communication"
  value       = aws_instance.control_plane.private_ip
}

# 생성된 모든 AWS Worker의 Private IP 목록
output "worker_private_ips" {
  description = "Worker private IPs used inside the AWS VPC"
  value       = aws_instance.worker[*].private_ip
}

# Control Plane을 Kubernetes Node로 구성할 때 필요한 AWS 메타데이터
output "control_plane_node_metadata" {
  description = "Metadata Ansible needs to configure the Kubernetes control-plane Node"
  value = {
    name              = local.control_plane_name
    platform          = local.platform
    instance_id       = aws_instance.control_plane.id
    instance_type     = aws_instance.control_plane.instance_type
    region            = var.aws_region
    availability_zone = aws_instance.control_plane.availability_zone
    # Kubernetes가 AWS 인스턴스를 식별할 때 사용하는 provider ID 형식
    provider_id = format("aws:///%s/%s", aws_instance.control_plane.availability_zone, aws_instance.control_plane.id)
  }
}

# worker_count만큼 생성된 Worker의 메타데이터 목록
output "worker_node_metadata" {
  description = "Metadata Ansible needs to configure AWS Kubernetes worker Nodes"
  value = [
    for index, instance in aws_instance.worker : {
      name              = local.worker_names[index]
      platform          = local.platform
      instance_id       = instance.id
      instance_type     = instance.instance_type
      region            = var.aws_region
      availability_zone = instance.availability_zone
      provider_id       = format("aws:///%s/%s", instance.availability_zone, instance.id)
    }
  ]
}

output "worker_role_name" {
  description = "IAM role name attached to service worker nodes when enabled"
  value       = var.enable_worker_instance_profile ? aws_iam_role.worker[0].name : null
}

output "worker_role_arn" {
  description = "IAM role ARN attached to service worker nodes when enabled"
  value       = var.enable_worker_instance_profile ? aws_iam_role.worker[0].arn : null
}

output "worker_instance_profile_name" {
  description = "IAM instance profile name attached to service worker nodes when enabled"
  value       = var.enable_worker_instance_profile ? aws_iam_instance_profile.worker[0].name : null
}

output "control_plane_role_name" {
  description = "IAM role name attached to the control plane node when enabled"
  value       = var.enable_control_plane_instance_profile ? aws_iam_role.control_plane[0].name : null
}
