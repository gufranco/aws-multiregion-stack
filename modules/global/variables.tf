# =============================================================================
# Global Module - Variables
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-30 characters, lowercase alphanumeric with hyphens, starting with letter."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "domain_name" {
  description = "Primary domain name for Route53 hosted zone"
  type        = string
  default     = ""
}

variable "create_hosted_zone" {
  description = "Whether to create a new Route53 hosted zone or use existing"
  type        = bool
  default     = false
}

variable "existing_hosted_zone_id" {
  description = "ID of existing Route53 hosted zone (if not creating new)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Region Configuration
# -----------------------------------------------------------------------------

variable "regions" {
  description = "Map of AWS regions with their configuration"
  type = map(object({
    enabled     = bool
    aws_region  = string
    is_primary  = bool
    tier        = string # primary, secondary, tertiary
    cidr_block  = string
    ecs_api_min = number
    ecs_api_max = number
    enable_nat  = bool
  }))

  validation {
    condition = length([
      for key, region in var.regions : key
      if region.is_primary && region.enabled
    ]) == 1
    error_message = "Exactly one region must be marked as primary."
  }
}

# -----------------------------------------------------------------------------
# Global Accelerator Configuration
# -----------------------------------------------------------------------------

variable "enable_global_accelerator" {
  description = "Enable AWS Global Accelerator for global traffic routing"
  type        = bool
  default     = true
}

variable "global_accelerator_flow_logs_enabled" {
  description = "Enable flow logs for Global Accelerator"
  type        = bool
  default     = true
}

variable "global_accelerator_flow_logs_bucket" {
  description = "S3 bucket name for Global Accelerator flow logs"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# ECR Configuration
# -----------------------------------------------------------------------------

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["api", "worker"]
}

variable "ecr_image_tag_mutability" {
  description = "Tag mutability setting for ECR repositories"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push to ECR"
  type        = bool
  default     = true
}

variable "ecr_lifecycle_policy_count" {
  description = "Number of images to retain in ECR (older images are deleted)"
  type        = number
  default     = 30
}

variable "ecr_kms_key_arn" {
  description = "KMS key ARN for ECR encryption (leave empty for AES256)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudFront Configuration (Optional)
# -----------------------------------------------------------------------------

variable "enable_cloudfront" {
  description = "Enable CloudFront CDN for static assets"
  type        = bool
  default     = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
