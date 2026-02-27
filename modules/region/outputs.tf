# =============================================================================
# Region Module - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "NAT Gateway public IPs"
  value       = var.enable_nat ? aws_eip.nat[*].public_ip : []
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "ecs_api_security_group_id" {
  description = "ECS API security group ID"
  value       = aws_security_group.ecs_api.id
}

output "ecs_worker_security_group_id" {
  description = "ECS Worker security group ID"
  value       = aws_security_group.ecs_worker.id
}

output "lambda_security_group_id" {
  description = "Lambda security group ID"
  value       = aws_security_group.lambda.id
}

output "database_security_group_id" {
  description = "Database security group ID"
  value       = aws_security_group.database.id
}

output "redis_security_group_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis.id
}

# -----------------------------------------------------------------------------
# ALB Outputs
# -----------------------------------------------------------------------------

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = aws_lb.main.zone_id
}

output "alb_target_group_arn" {
  description = "ALB target group ARN for API"
  value       = aws_lb_target_group.api.arn
}

# -----------------------------------------------------------------------------
# ECS Outputs
# -----------------------------------------------------------------------------

output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_api_service_name" {
  description = "ECS API service name"
  value       = aws_ecs_service.api.name
}

output "ecs_worker_service_name" {
  description = "ECS Worker service name"
  value       = aws_ecs_service.worker.name
}

# -----------------------------------------------------------------------------
# SQS Outputs
# -----------------------------------------------------------------------------

output "sqs_order_processing_url" {
  description = "Order processing SQS queue URL"
  value       = aws_sqs_queue.order_processing.url
}

output "sqs_order_processing_arn" {
  description = "Order processing SQS queue ARN"
  value       = aws_sqs_queue.order_processing.arn
}

output "sqs_notification_url" {
  description = "Notification SQS queue URL"
  value       = aws_sqs_queue.notification.url
}

output "sqs_notification_arn" {
  description = "Notification SQS queue ARN"
  value       = aws_sqs_queue.notification.arn
}

output "sqs_dlq_url" {
  description = "DLQ URL"
  value       = aws_sqs_queue.dlq.url
}

output "sqs_dlq_arn" {
  description = "DLQ ARN"
  value       = aws_sqs_queue.dlq.arn
}

output "sqs_fifo_url" {
  description = "FIFO queue URL"
  value       = aws_sqs_queue.order_fifo.url
}

# -----------------------------------------------------------------------------
# SNS Outputs
# -----------------------------------------------------------------------------

output "sns_order_events_arn" {
  description = "Order events SNS topic ARN"
  value       = aws_sns_topic.order_events.arn
}

output "sns_notifications_arn" {
  description = "Notifications SNS topic ARN"
  value       = aws_sns_topic.notifications.arn
}

output "sns_alerts_arn" {
  description = "Alerts SNS topic ARN"
  value       = aws_sns_topic.alerts.arn
}

# -----------------------------------------------------------------------------
# Lambda Outputs
# -----------------------------------------------------------------------------

output "lambda_order_processor_arn" {
  description = "Order processor Lambda ARN"
  value       = aws_lambda_function.order_processor.arn
}

output "lambda_notification_handler_arn" {
  description = "Notification handler Lambda ARN"
  value       = aws_lambda_function.notification_handler.arn
}

output "lambda_dlq_handler_arn" {
  description = "DLQ handler Lambda ARN"
  value       = aws_lambda_function.dlq_handler.arn
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "ecs_execution_role_arn" {
  description = "ECS execution role ARN"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_api_role_arn" {
  description = "ECS API task role ARN"
  value       = aws_iam_role.ecs_task_api.arn
}

output "ecs_task_worker_role_arn" {
  description = "ECS Worker task role ARN"
  value       = aws_iam_role.ecs_task_worker.arn
}

output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_api" {
  description = "API CloudWatch log group name"
  value       = aws_cloudwatch_log_group.api.name
}

output "cloudwatch_log_group_worker" {
  description = "Worker CloudWatch log group name"
  value       = aws_cloudwatch_log_group.worker.name
}

# -----------------------------------------------------------------------------
# Bastion Host
# -----------------------------------------------------------------------------

output "bastion_public_ip" {
  description = "Bastion host public IP address"
  value       = var.enable_bastion ? aws_instance.bastion[0].public_ip : ""
}

output "bastion_public_dns" {
  description = "Bastion host public DNS name"
  value       = var.enable_bastion ? aws_instance.bastion[0].public_dns : ""
}

output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : ""
}

# -----------------------------------------------------------------------------
# Region Info
# -----------------------------------------------------------------------------

output "region_info" {
  description = "Region information"
  value = {
    region_key = var.region_key
    aws_region = var.aws_region
    is_primary = var.is_primary
    tier       = var.tier
  }
}
