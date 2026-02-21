# =============================================================================
# CloudWatch Dashboards
# =============================================================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-${var.aws_region}"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Overview
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.project_name} - ${var.environment} - ${var.aws_region}\n**Region Dashboard**"
        }
      },

      # Row 2: ECS API Service
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "API Service - CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_api_service_name, { stat = "Average", period = 60 }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              { value = var.api_cpu_threshold, label = "Threshold", color = "#ff7f0e" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "API Service - Memory Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_api_service_name, { stat = "Average", period = 60 }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              { value = var.api_memory_threshold, label = "Threshold", color = "#ff7f0e" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "API Service - Running Tasks"
          region = var.aws_region
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_api_service_name, { stat = "Average", period = 60 }]
          ]
        }
      },

      # Row 3: ALB Metrics
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ALB - Request Count"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ALB - Target Response Time"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50", period = 60, label = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p90", period = 60, label = "p90" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99", period = 60, label = "p99" }]
          ]
          annotations = {
            horizontal = [
              { value = var.latency_p99_threshold / 1000, label = "P99 Threshold", color = "#ff7f0e" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "ALB - HTTP Status Codes"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60, label = "2XX", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60, label = "4XX", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60, label = "5XX", color = "#d62728" }]
          ]
        }
      },

      # Row 4: Worker Service
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Worker Service - CPU & Memory"
          region = var.aws_region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_worker_service_name, { stat = "Average", period = 60, label = "CPU" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_worker_service_name, { stat = "Average", period = 60, label = "Memory" }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "SQS - Messages in Queue"
          region = var.aws_region
          metrics = [
            for queue_name in var.sqs_queue_names : [
              "AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", queue_name, { stat = "Sum", period = 60, label = queue_name }
            ]
          ]
        }
      },

      # Row 5: DLQ and Errors
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 12
        height = 6
        properties = {
          title  = "Dead Letter Queue"
          region = var.aws_region
          metrics = var.sqs_dlq_name != "" ? [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.sqs_dlq_name, { stat = "Sum", period = 60, color = "#d62728" }]
          ] : []
          annotations = {
            horizontal = [
              { value = var.dlq_message_threshold, label = "Alert Threshold", color = "#ff7f0e" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 19
        width  = 12
        height = 6
        properties = {
          title  = "Error Rate"
          region = var.aws_region
          metrics = [
            [{
              expression = "m1/(m1+m2)*100"
              label      = "Error Rate %"
              id         = "e1"
              color      = "#d62728"
            }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60, id = "m1", visible = false }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", period = 60, id = "m2", visible = false }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              { value = var.error_rate_threshold, label = "Threshold", color = "#ff7f0e" }
            ]
          }
        }
      }
    ]
  })
}
