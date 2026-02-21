# =============================================================================
# AWS CodeDeploy for ECS Blue/Green Deployments
# =============================================================================

# -----------------------------------------------------------------------------
# CodeDeploy Application
# -----------------------------------------------------------------------------

resource "aws_codedeploy_app" "api" {
  count = var.enable_blue_green ? 1 : 0

  compute_platform = "ECS"
  name             = "${local.name_prefix}-api"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-api-codedeploy"
  })
}

# -----------------------------------------------------------------------------
# CodeDeploy Deployment Group
# -----------------------------------------------------------------------------

resource "aws_codedeploy_deployment_group" "api" {
  count = var.enable_blue_green && var.acm_certificate_arn != "" ? 1 : 0

  app_name               = aws_codedeploy_app.api[0].name
  deployment_group_name  = "${local.name_prefix}-api"
  deployment_config_name = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
  service_role_arn       = aws_iam_role.codedeploy[0].arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.api.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.https[0].arn]
      }

      target_group {
        name = aws_lb_target_group.api.name
      }

      target_group {
        name = aws_lb_target_group.api_green[0].name
      }
    }
  }

  alarm_configuration {
    enabled = true
    alarms  = var.deployment_alarm_names
  }

  tags = merge(local.common_tags, var.tags)
}

# -----------------------------------------------------------------------------
# Green Target Group (for Blue/Green)
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "api_green" {
  count = var.enable_blue_green ? 1 : 0

  name        = "${local.name_prefix}-api-green"
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
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-api-green"
  })
}

# -----------------------------------------------------------------------------
# CodeDeploy IAM Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "codedeploy" {
  count = var.enable_blue_green ? 1 : 0

  name = "${local.name_prefix}-codedeploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, var.tags)
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = var.enable_blue_green ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
