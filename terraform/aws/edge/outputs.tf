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

output "target_group_arn" {
  description = "Target group forwarding TCP traffic to the Istio gateway HTTP NodePort"
  value       = aws_lb_target_group.http.arn
}

output "allowed_ingress_cidrs" {
  description = "Source CIDRs currently allowed to reach the audio NLB"
  value       = sort(var.allowed_ingress_cidrs)
}

output "public_read_only_access" {
  description = "Whether the NLB open internet CIDR relies on the Istio public read-only boundary"
  value       = var.public_read_only_access
}

output "public_host" {
  description = "Configured public host or null when the Route53 record is disabled"
  value       = var.create_dns_record ? var.public_host : null
}

output "public_url" {
  description = "Address to open in a browser"
  value = (
    var.enable_tls && var.create_dns_record ? "https://${var.public_host}"
    : var.create_dns_record ? "http://${var.public_host}"
    : "http://${aws_lb.audio.dns_name}"
  )
}

output "certificate_arn" {
  description = "ACM certificate ARN used by the NLB TLS listener"
  value       = var.enable_tls ? aws_acm_certificate.audio[0].arn : null
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager when DNS-01 IAM is enabled"
  value       = var.enable_cert_manager_iam ? aws_iam_role.cert_manager[0].arn : null
}

output "registered_worker_instance_ids" {
  description = "AWS Worker instance IDs registered in the NLB target group"
  value       = sort(keys(local.worker_nodes))
}
