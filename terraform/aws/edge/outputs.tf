output "nlb_arn" {
  description = "ARN of the public audio NLB"
  value       = aws_lb.audio.arn
}

output "nlb_dns_name" {
  description = "AWS-provided DNS name used before the public Route53 record is enabled"
  value       = aws_lb.audio.dns_name
}

output "nlb_zone_id" {
  description = "Canonical hosted zone ID of the public audio NLB"
  value       = aws_lb.audio.zone_id
}

output "nlb_security_group_id" {
  description = "Security group ID owned by the Edge state"
  value       = aws_security_group.audio_nlb.id
}

output "audio_ingress_node_ports" {
  description = "NodePort contract shared with the Istio ingress gateway Service"
  value       = local.node_ports
}

output "target_group_arns" {
  description = "Target groups forwarding TCP traffic to the Istio gateway NodePorts"
  value = {
    http  = aws_lb_target_group.http.arn
    https = aws_lb_target_group.https.arn
  }
}

output "public_host" {
  description = "Configured public host or null when the Route53 record is disabled"
  value       = var.create_dns_record ? var.public_host : null
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager when DNS-01 IAM is enabled"
  value       = var.enable_cert_manager_iam ? aws_iam_role.cert_manager[0].arn : null
}

output "registered_worker_instance_ids" {
  description = "AWS Worker instance IDs registered in both NLB target groups"
  value       = sort(keys(local.worker_nodes))
}
