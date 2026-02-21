# =============================================================================
# Lambda Functions
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Lambdas
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_order_processor" {
  name              = "/aws/lambda/${local.name_prefix}-order-processor"
  retention_in_days = 30

  tags = merge(local.common_tags, var.tags)
}

resource "aws_cloudwatch_log_group" "lambda_notification_handler" {
  name              = "/aws/lambda/${local.name_prefix}-notification-handler"
  retention_in_days = 30

  tags = merge(local.common_tags, var.tags)
}

resource "aws_cloudwatch_log_group" "lambda_dlq_handler" {
  name              = "/aws/lambda/${local.name_prefix}-dlq-handler"
  retention_in_days = 30

  tags = merge(local.common_tags, var.tags)
}

# -----------------------------------------------------------------------------
# Order Processor Lambda
# -----------------------------------------------------------------------------
# Processes order events from SNS/SQS
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "order_processor" {
  function_name = "${local.name_prefix}-order-processor"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = var.lambda_runtime
  handler       = "index.handler"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  # Placeholder for actual code - will be deployed via CI/CD
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      NODE_ENV          = var.environment
      AWS_REGION_CUSTOM = var.aws_region
      REGION_KEY        = var.region_key
      IS_PRIMARY_REGION = tostring(var.is_primary)
      DATABASE_HOST     = var.database_endpoint
      DATABASE_PORT     = tostring(var.database_port)
      DATABASE_NAME     = var.database_name
      REDIS_HOST        = var.redis_endpoint
      REDIS_PORT        = tostring(var.redis_port)
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"
  }

  reserved_concurrent_executions = 100

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-order-processor"
  })

  depends_on = [aws_cloudwatch_log_group.lambda_order_processor]
}

# SQS trigger for order processor
resource "aws_lambda_event_source_mapping" "order_processor_sqs" {
  event_source_arn                   = aws_sqs_queue.order_processing.arn
  function_name                      = aws_lambda_function.order_processor.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  enabled                            = true

  scaling_config {
    maximum_concurrency = 50
  }

  function_response_types = ["ReportBatchItemFailures"]
}

# SNS trigger for order processor
resource "aws_lambda_permission" "order_processor_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_processor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.order_events.arn
}

resource "aws_sns_topic_subscription" "order_processor_lambda" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.order_processor.arn

  filter_policy = jsonencode({
    eventType = ["order.confirmed", "order.shipped"]
  })
}

# -----------------------------------------------------------------------------
# Notification Handler Lambda
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "notification_handler" {
  function_name = "${local.name_prefix}-notification-handler"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = var.lambda_runtime
  handler       = "index.handler"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      NODE_ENV          = var.environment
      AWS_REGION_CUSTOM = var.aws_region
      REGION_KEY        = var.region_key
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"
  }

  reserved_concurrent_executions = 50

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-notification-handler"
  })

  depends_on = [aws_cloudwatch_log_group.lambda_notification_handler]
}

resource "aws_lambda_event_source_mapping" "notification_handler_sqs" {
  event_source_arn                   = aws_sqs_queue.notification.arn
  function_name                      = aws_lambda_function.notification_handler.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  enabled                            = true

  function_response_types = ["ReportBatchItemFailures"]
}

# -----------------------------------------------------------------------------
# DLQ Handler Lambda
# -----------------------------------------------------------------------------

resource "aws_lambda_function" "dlq_handler" {
  function_name = "${local.name_prefix}-dlq-handler"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = var.lambda_runtime
  handler       = "index.handler"
  memory_size   = 128
  timeout       = 30

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      NODE_ENV          = var.environment
      AWS_REGION_CUSTOM = var.aws_region
      REGION_KEY        = var.region_key
      ALERTS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-dlq-handler"
  })

  depends_on = [aws_cloudwatch_log_group.lambda_dlq_handler]
}

resource "aws_lambda_event_source_mapping" "dlq_handler" {
  event_source_arn = aws_sqs_queue.dlq.arn
  function_name    = aws_lambda_function.dlq_handler.arn
  batch_size       = 1
  enabled          = true
}

# -----------------------------------------------------------------------------
# Lambda Placeholder Code
# -----------------------------------------------------------------------------

data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "/tmp/terraform-${var.project_name}-lambda-placeholder.zip"

  source {
    content  = <<-EOF
      exports.handler = async (event) => {
        console.log('Event:', JSON.stringify(event, null, 2));
        return { statusCode: 200, body: 'Placeholder' };
      };
    EOF
    filename = "index.js"
  }
}
