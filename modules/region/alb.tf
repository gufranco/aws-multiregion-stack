# =============================================================================
# Application Load Balancer
# =============================================================================

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout               = var.alb_idle_timeout
  enable_deletion_protection = var.environment == "prod"

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs && var.alb_access_logs_bucket != "" ? [1] : []
    content {
      bucket  = var.alb_access_logs_bucket
      prefix  = "alb/${local.name_prefix}"
      enabled = true
    }
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# -----------------------------------------------------------------------------
# Target Group - API
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "api" {
  name        = "${local.name_prefix}-api-tg"
  port        = var.api_container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-api-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# HTTP Listener
# -----------------------------------------------------------------------------
# When a certificate is provided, redirects HTTP to HTTPS.
# When no certificate is provided, forwards HTTP traffic directly.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.acm_certificate_arn != "" ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.acm_certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = var.acm_certificate_arn == "" ? aws_lb_target_group.api.arn : null
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-http-listener"
  })
}

# -----------------------------------------------------------------------------
# HTTPS Listener
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-https-listener"
  })
}

# -----------------------------------------------------------------------------
# Global Accelerator Endpoint
# -----------------------------------------------------------------------------
# Endpoint groups are created by the global module. The ALB ARN is exported
# as an output so the global module can attach it as an endpoint.

# -----------------------------------------------------------------------------
# Route53 Record for Regional ALB
# -----------------------------------------------------------------------------

resource "aws_route53_record" "alb" {
  count = var.route53_zone_id != "" && var.domain_name != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = "alb.${var.aws_region}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
