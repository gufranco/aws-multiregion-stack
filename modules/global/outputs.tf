# =============================================================================
# Global Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Global Accelerator Outputs
# -----------------------------------------------------------------------------

output "global_accelerator_id" {
  description = "ID of the Global Accelerator"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_accelerator.main[0].id : null
}

output "global_accelerator_arn" {
  description = "ARN of the Global Accelerator"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_accelerator.main[0].id : null
}

output "global_accelerator_dns_name" {
  description = "DNS name of the Global Accelerator"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_accelerator.main[0].dns_name : null
}

output "global_accelerator_hosted_zone_id" {
  description = "Route53 hosted zone ID for Global Accelerator alias records"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_accelerator.main[0].hosted_zone_id : null
}

output "global_accelerator_ip_addresses" {
  description = "Static IP addresses of the Global Accelerator"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_accelerator.main[0].ip_sets[0].ip_addresses : []
}

output "global_accelerator_listener_http_arn" {
  description = "ARN of the HTTP listener"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_listener.http[0].arn : null
}

output "global_accelerator_listener_https_arn" {
  description = "ARN of the HTTPS listener"
  value       = var.enable_global_accelerator ? aws_globalaccelerator_listener.https[0].arn : null
}

output "global_accelerator_endpoint_groups" {
  description = "Map of regional endpoint group ARNs"
  value = var.enable_global_accelerator ? {
    for key, eg in aws_globalaccelerator_endpoint_group.regions : key => eg.arn
  } : {}
}

# -----------------------------------------------------------------------------
# Route53 Outputs
# -----------------------------------------------------------------------------

output "route53_zone_id" {
  description = "ID of the Route53 hosted zone"
  value       = local.hosted_zone_id
}

output "route53_zone_name" {
  description = "Name of the Route53 hosted zone"
  value       = local.hosted_zone_name
}

output "route53_name_servers" {
  description = "Name servers for the hosted zone (if created)"
  value       = var.create_hosted_zone && length(aws_route53_zone.main) > 0 ? aws_route53_zone.main[0].name_servers : []
}

output "route53_health_check_ids" {
  description = "Map of regional health check IDs"
  value = {
    for key, hc in aws_route53_health_check.regional : key => hc.id
  }
}

# -----------------------------------------------------------------------------
# ECR Outputs
# -----------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "Map of ECR repository URLs"
  value = {
    for name, repo in aws_ecr_repository.main : name => repo.repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map of ECR repository ARNs"
  value = {
    for name, repo in aws_ecr_repository.main : name => repo.arn
  }
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# Region Configuration Outputs
# -----------------------------------------------------------------------------

output "enabled_regions" {
  description = "Map of enabled regions with their configuration"
  value       = local.enabled_regions
}

output "primary_region" {
  description = "Primary region configuration"
  value       = local.primary_region
}

output "primary_region_key" {
  description = "Key of the primary region"
  value       = local.primary_region_key
}

# -----------------------------------------------------------------------------
# Account Information
# -----------------------------------------------------------------------------

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_partition" {
  description = "AWS partition (aws, aws-cn, aws-us-gov)"
  value       = data.aws_partition.current.partition
}
