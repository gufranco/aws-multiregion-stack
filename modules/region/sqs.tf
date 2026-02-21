# =============================================================================
# SQS Queues
# =============================================================================

# -----------------------------------------------------------------------------
# Dead Letter Queue (DLQ)
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                       = "${local.name_prefix}-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-dlq"
    Type = "dlq"
  })
}

# -----------------------------------------------------------------------------
# Order Processing Queue
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "order_processing" {
  name                       = "${local.name_prefix}-order-processing"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  receive_wait_time_seconds  = 20 # Long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-order-processing"
    Type = "processing"
  })
}

# -----------------------------------------------------------------------------
# Notification Queue
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "notification" {
  name                       = "${local.name_prefix}-notification"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-notification"
    Type = "notification"
  })
}

# -----------------------------------------------------------------------------
# FIFO Queue (for ordered processing)
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "order_fifo" {
  name                        = "${local.name_prefix}-order.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = var.sqs_message_retention_seconds
  visibility_timeout_seconds  = var.sqs_visibility_timeout_seconds
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  sqs_managed_sse_enabled     = true

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-order-fifo"
    Type = "fifo"
  })
}

# -----------------------------------------------------------------------------
# Queue Policies
# -----------------------------------------------------------------------------

resource "aws_sqs_queue_policy" "order_processing" {
  queue_url = aws_sqs_queue.order_processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNS"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.order_processing.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.order_events.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "notification" {
  queue_url = aws_sqs_queue.notification.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNS"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.notification.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.notifications.arn
          }
        }
      }
    ]
  })
}
