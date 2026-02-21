# =============================================================================
# Security Groups
# =============================================================================

# -----------------------------------------------------------------------------
# ALB Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-http" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-https" })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To ECS tasks"
  from_port                    = var.api_container_port
  to_port                      = var.api_container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_api.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-to-ecs" })
}

# -----------------------------------------------------------------------------
# ECS API Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "ecs_api" {
  name        = "${local.name_prefix}-ecs-api-sg"
  description = "Security group for ECS API tasks"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecs-api-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ecs_api_from_alb" {
  security_group_id            = aws_security_group.ecs_api.id
  description                  = "From ALB"
  from_port                    = var.api_container_port
  to_port                      = var.api_container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-from-alb" })
}

resource "aws_vpc_security_group_egress_rule" "ecs_api_to_internet" {
  security_group_id = aws_security_group.ecs_api.id
  description       = "To internet (via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-to-internet" })
}

# -----------------------------------------------------------------------------
# ECS Worker Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "ecs_worker" {
  name        = "${local.name_prefix}-ecs-worker-sg"
  description = "Security group for ECS Worker tasks"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-ecs-worker-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "ecs_worker_to_internet" {
  security_group_id = aws_security_group.ecs_worker.id
  description       = "To internet (via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-worker-to-internet" })
}

# -----------------------------------------------------------------------------
# Lambda Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-lambda-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_internet" {
  security_group_id = aws_security_group.lambda.id
  description       = "To internet (via NAT)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-lambda-to-internet" })
}

# -----------------------------------------------------------------------------
# Database Security Group (for RDS/Aurora)
# -----------------------------------------------------------------------------

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-database-sg"
  description = "Security group for database access"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-database-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_ecs_api" {
  security_group_id            = aws_security_group.database.id
  description                  = "From ECS API"
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_api.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-from-api" })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_ecs_worker" {
  security_group_id            = aws_security_group.database.id
  description                  = "From ECS Worker"
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_worker.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-from-worker" })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_lambda" {
  security_group_id            = aws_security_group.database.id
  description                  = "From Lambda"
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-from-lambda" })
}

# -----------------------------------------------------------------------------
# Redis Security Group (for ElastiCache)
# -----------------------------------------------------------------------------

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Security group for Redis access"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-redis-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs_api" {
  security_group_id            = aws_security_group.redis.id
  description                  = "From ECS API"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_api.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-from-api" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs_worker" {
  security_group_id            = aws_security_group.redis.id
  description                  = "From ECS Worker"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_worker.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-from-worker" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_lambda" {
  security_group_id            = aws_security_group.redis.id
  description                  = "From Lambda"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-from-lambda" })
}

# -----------------------------------------------------------------------------
# VPC Endpoints Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from VPC"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.cidr_block

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpce-https" })
}
