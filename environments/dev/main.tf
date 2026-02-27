# =============================================================================
# Development Environment
# =============================================================================
# This is the main entry point for the dev environment.
# It instantiates all modules with dev-specific configuration.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration - uncomment for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

# Single provider that targets LocalStack when use_localstack=true,
# or real AWS when use_localstack=false. Provider references in module
# blocks must be static, so we consolidate into one configurable provider.
provider "aws" {
  region = local.primary_region

  access_key                  = var.use_localstack ? "test" : null
  secret_key                  = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  endpoints {
    acm                    = var.use_localstack ? var.localstack_endpoint : null
    apigateway             = var.use_localstack ? var.localstack_endpoint : null
    cloudformation         = var.use_localstack ? var.localstack_endpoint : null
    cloudwatch             = var.use_localstack ? var.localstack_endpoint : null
    cloudwatchlogs         = var.use_localstack ? var.localstack_endpoint : null
    dynamodb               = var.use_localstack ? var.localstack_endpoint : null
    ec2                    = var.use_localstack ? var.localstack_endpoint : null
    ecr                    = var.use_localstack ? var.localstack_endpoint : null
    ecs                    = var.use_localstack ? var.localstack_endpoint : null
    elasticache            = var.use_localstack ? var.localstack_endpoint : null
    elasticloadbalancing   = var.use_localstack ? var.localstack_endpoint : null
    elasticloadbalancingv2 = var.use_localstack ? var.localstack_endpoint : null
    events                 = var.use_localstack ? var.localstack_endpoint : null
    globalaccelerator      = var.use_localstack ? var.localstack_endpoint : null
    iam                    = var.use_localstack ? var.localstack_endpoint : null
    kinesis                = var.use_localstack ? var.localstack_endpoint : null
    kms                    = var.use_localstack ? var.localstack_endpoint : null
    lambda                 = var.use_localstack ? var.localstack_endpoint : null
    rds                    = var.use_localstack ? var.localstack_endpoint : null
    route53                = var.use_localstack ? var.localstack_endpoint : null
    s3                     = var.use_localstack ? var.localstack_endpoint : null
    secretsmanager         = var.use_localstack ? var.localstack_endpoint : null
    ses                    = var.use_localstack ? var.localstack_endpoint : null
    sns                    = var.use_localstack ? var.localstack_endpoint : null
    sqs                    = var.use_localstack ? var.localstack_endpoint : null
    ssm                    = var.use_localstack ? var.localstack_endpoint : null
    stepfunctions          = var.use_localstack ? var.localstack_endpoint : null
    sts                    = var.use_localstack ? var.localstack_endpoint : null
  }

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------

locals {
  primary_region = "us-east-1"

  # Filter enabled regions
  enabled_regions = {
    for key, region in var.regions : key => region
    if region.enabled
  }
}

# -----------------------------------------------------------------------------
# Global Module
# -----------------------------------------------------------------------------

module "global" {
  source = "../../modules/global"

  # Provider configured via use_localstack variable

  project_name              = var.project_name
  environment               = var.environment
  domain_name               = var.domain_name
  create_hosted_zone        = var.create_hosted_zone
  existing_hosted_zone_id   = var.existing_hosted_zone_id
  regions                   = var.regions
  enable_global_accelerator = var.enable_global_accelerator
  ecr_repositories          = var.ecr_repositories

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Region Modules (one per enabled region)
# -----------------------------------------------------------------------------

module "region_us_east_1" {
  source = "../../modules/region"
  count  = lookup(var.regions, "us_east_1", { enabled = false }).enabled ? 1 : 0

  # Provider configured via use_localstack variable

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.regions["us_east_1"].aws_region
  region_key   = "us_east_1"
  is_primary   = var.regions["us_east_1"].is_primary
  tier         = var.regions["us_east_1"].tier
  cidr_block   = var.regions["us_east_1"].cidr_block
  enable_nat   = var.regions["us_east_1"].enable_nat

  ecs_api_min      = var.regions["us_east_1"].ecs_api_min
  ecs_api_max      = var.regions["us_east_1"].ecs_api_max
  ecs_api_desired  = var.ecs_api_desired
  use_fargate_spot = var.use_fargate_spot

  api_image    = "${module.global.ecr_repository_urls["api"]}:${var.image_tag}"
  worker_image = "${module.global.ecr_repository_urls["worker"]}:${var.image_tag}"

  global_accelerator_endpoint_group_arn = var.enable_global_accelerator ? module.global.global_accelerator_endpoint_groups["us_east_1"] : ""
  route53_zone_id                       = module.global.route53_zone_id
  domain_name                           = var.domain_name

  database_endpoint      = module.data.rds_proxy_endpoint
  database_read_endpoint = module.data.rds_proxy_read_only_endpoint
  database_port          = 5432
  database_name          = var.aurora_database_name
  database_secret_arn    = module.data.aurora_master_secret_arn

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Data Module
# -----------------------------------------------------------------------------

module "data" {
  source = "../../modules/data"

  # Provider configured via use_localstack variable

  project_name = var.project_name
  environment  = var.environment
  regions      = var.regions

  # Aurora configuration
  aurora_engine_version          = var.aurora_engine_version
  aurora_serverless_min_capacity = var.aurora_serverless_min_capacity
  aurora_serverless_max_capacity = var.aurora_serverless_max_capacity
  aurora_database_name           = var.aurora_database_name
  aurora_writer_count            = 1     # Single writer for dev
  aurora_reader_count            = 0     # No readers for dev
  aurora_skip_final_snapshot     = true  # Safe for dev
  aurora_deletion_protection     = false # Safe for dev

  # DynamoDB configuration
  dynamodb_billing_mode = "PAY_PER_REQUEST"

  # Redis configuration
  redis_node_type          = var.redis_node_type
  redis_num_cache_clusters = 1 # Single node for dev

  # Network configuration from region modules
  vpc_ids = {
    us_east_1 = length(module.region_us_east_1) > 0 ? module.region_us_east_1[0].vpc_id : ""
  }

  private_subnet_ids = {
    us_east_1 = length(module.region_us_east_1) > 0 ? module.region_us_east_1[0].private_subnet_ids : []
  }

  database_security_group_ids = {
    us_east_1 = length(module.region_us_east_1) > 0 ? module.region_us_east_1[0].database_security_group_id : ""
  }

  redis_security_group_ids = {
    us_east_1 = length(module.region_us_east_1) > 0 ? module.region_us_east_1[0].redis_security_group_id : ""
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "global_accelerator_ips" {
  description = "Global Accelerator IP addresses"
  value       = module.global.global_accelerator_ip_addresses
}

output "global_accelerator_dns" {
  description = "Global Accelerator DNS name"
  value       = module.global.global_accelerator_dns_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.global.ecr_repository_urls
}

output "region_us_east_1_alb_dns" {
  description = "US East 1 ALB DNS name"
  value       = length(module.region_us_east_1) > 0 ? module.region_us_east_1[0].alb_dns_name : ""
}

output "aurora_endpoint" {
  description = "Aurora primary endpoint (direct, bypasses proxy)"
  value       = module.data.aurora_primary_endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy read/write endpoint"
  value       = module.data.rds_proxy_endpoint
}

output "rds_proxy_read_only_endpoint" {
  description = "RDS Proxy read-only endpoint"
  value       = module.data.rds_proxy_read_only_endpoint
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = module.data.redis_primary_endpoint
}

output "dynamodb_tables" {
  description = "DynamoDB table names"
  value = {
    sessions = module.data.dynamodb_sessions_table_name
    orders   = module.data.dynamodb_orders_table_name
    events   = module.data.dynamodb_events_table_name
  }
}
