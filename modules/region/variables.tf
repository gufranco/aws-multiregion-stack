# =============================================================================
# Region Module - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Basic Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for this module instance"
  type        = string
}

variable "region_key" {
  description = "Unique key for this region (e.g., us_east_1)"
  type        = string
}

variable "is_primary" {
  description = "Whether this is the primary region"
  type        = bool
  default     = false
}

variable "tier" {
  description = "Region tier (primary, secondary, tertiary)"
  type        = string
  default     = "secondary"

  validation {
    condition     = contains(["primary", "secondary", "tertiary"], var.tier)
    error_message = "Tier must be one of: primary, secondary, tertiary."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid CIDR notation (e.g., 10.0.0.0/16)."
  }
}

variable "enable_nat" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway instead of one per AZ (cost saving for non-prod)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# ECS Configuration
# -----------------------------------------------------------------------------

variable "ecs_api_min" {
  description = "Minimum number of API tasks"
  type        = number
  default     = 2
}

variable "ecs_api_max" {
  description = "Maximum number of API tasks"
  type        = number
  default     = 20
}

variable "ecs_api_desired" {
  description = "Desired number of API tasks"
  type        = number
  default     = 2
}

variable "ecs_worker_min" {
  description = "Minimum number of Worker tasks"
  type        = number
  default     = 1
}

variable "ecs_worker_max" {
  description = "Maximum number of Worker tasks"
  type        = number
  default     = 10
}

variable "ecs_worker_desired" {
  description = "Desired number of Worker tasks"
  type        = number
  default     = 1
}

variable "ecs_api_cpu" {
  description = "CPU units for API tasks (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "ecs_api_memory" {
  description = "Memory (MiB) for API tasks"
  type        = number
  default     = 1024
}

variable "ecs_worker_cpu" {
  description = "CPU units for Worker tasks"
  type        = number
  default     = 256
}

variable "ecs_worker_memory" {
  description = "Memory (MiB) for Worker tasks"
  type        = number
  default     = 512
}

variable "ecs_enable_execute_command" {
  description = "Enable ECS Exec for debugging (should be false in production)"
  type        = bool
  default     = false
}

variable "use_fargate_spot" {
  description = "Use Fargate Spot for worker tasks"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Container Images
# -----------------------------------------------------------------------------

variable "api_image" {
  description = "Docker image URI for API service"
  type        = string
}

variable "worker_image" {
  description = "Docker image URI for Worker service"
  type        = string
}

# -----------------------------------------------------------------------------
# ALB Configuration
# -----------------------------------------------------------------------------

variable "alb_internal" {
  description = "Whether ALB is internal (not internet-facing)"
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logs"
  type        = bool
  default     = true
}

variable "alb_access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# SSL/TLS
# -----------------------------------------------------------------------------

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for HTTPS"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for this region's ALB"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

variable "database_endpoint" {
  description = "Database endpoint (from data module)"
  type        = string
  default     = ""
}

variable "database_read_endpoint" {
  description = "Database read-only endpoint (from data module)"
  type        = string
  default     = ""
}

variable "database_port" {
  description = "Database port"
  type        = number
  default     = 5432

  validation {
    condition     = var.database_port > 0 && var.database_port <= 65535
    error_message = "database_port must be between 1 and 65535."
  }
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = ""
}

variable "database_secret_arn" {
  description = "ARN of Secrets Manager secret for database credentials"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Cache
# -----------------------------------------------------------------------------

variable "redis_endpoint" {
  description = "Redis endpoint (from data module)"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

# -----------------------------------------------------------------------------
# Messaging
# -----------------------------------------------------------------------------

variable "sqs_message_retention_seconds" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 1209600 # 14 days
}

variable "sqs_visibility_timeout_seconds" {
  description = "SQS visibility timeout in seconds"
  type        = number
  default     = 60
}

variable "sns_subscriptions" {
  description = "Map of SNS topic to SQS queue subscriptions"
  type = map(object({
    topic_name    = string
    queue_name    = string
    filter_policy = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Lambda
# -----------------------------------------------------------------------------

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Global Accelerator Integration
# -----------------------------------------------------------------------------

variable "global_accelerator_endpoint_group_arn" {
  description = "ARN of Global Accelerator endpoint group for this region"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Route53 Integration
# -----------------------------------------------------------------------------

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Blue/Green Deployment
# -----------------------------------------------------------------------------

variable "enable_blue_green" {
  description = "Enable Blue/Green deployments with CodeDeploy"
  type        = bool
  default     = false
}

variable "deployment_alarm_names" {
  description = "CloudWatch alarm names that trigger deployment rollback"
  type        = list(string)
  default     = []
}

variable "api_container_port" {
  description = "Container port for API service"
  type        = number
  default     = 3000
}

# -----------------------------------------------------------------------------
# Bastion Host
# -----------------------------------------------------------------------------

variable "enable_bastion" {
  description = "Enable a bastion host for SSH access to private resources"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t4g.nano"
}

variable "bastion_key_name" {
  description = "EC2 key pair name for bastion SSH access"
  type        = string
  default     = ""
}

variable "bastion_allowed_cidr" {
  description = "CIDR block allowed to SSH into the bastion (e.g., your IP: 203.0.113.10/32)"
  type        = string
  default     = "0.0.0.0/0"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
