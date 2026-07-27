output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = values(aws_subnet.public)[*].id
}

output "control_plane_public_ip" {
  description = "Stable Elastic IP of the control-plane node"
  value       = aws_eip.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP used for cluster-internal communication"
  value       = aws_instance.control_plane.private_ip
}

output "worker_public_ips" {
  description = "Worker public IPs used for initial administration"
  value       = aws_instance.worker[*].public_ip
}

output "worker_private_ips" {
  description = "Worker private IPs used inside the AWS VPC"
  value       = aws_instance.worker[*].private_ip
}

output "control_plane_node_metadata" {
  description = "Metadata Ansible needs to configure the Kubernetes control-plane Node"
  value = {
    name              = local.control_plane_name
    instance_id       = aws_instance.control_plane.id
    instance_type     = aws_instance.control_plane.instance_type
    region            = var.aws_region
    availability_zone = aws_instance.control_plane.availability_zone
    provider_id       = format("aws:///%s/%s", aws_instance.control_plane.availability_zone, aws_instance.control_plane.id)
  }
}

output "worker_node_metadata" {
  description = "Metadata Ansible needs to configure AWS Kubernetes worker Nodes"
  value = [
    for index, instance in aws_instance.worker : {
      name              = local.worker_names[index]
      instance_id       = instance.id
      instance_type     = instance.instance_type
      region            = var.aws_region
      availability_zone = instance.availability_zone
      provider_id       = format("aws:///%s/%s", instance.availability_zone, instance.id)
    }
  ]
}

output "ssh_control_plane_command" {
  description = "SSH command for the control-plane node"
  value       = "ssh ubuntu@${aws_eip.control_plane.public_ip}"
}
