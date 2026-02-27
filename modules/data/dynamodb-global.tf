# =============================================================================
# DynamoDB Global Tables
# =============================================================================
# DynamoDB Global Tables provide multi-region, multi-master replication.
# All regions can read and write, with automatic conflict resolution.
# =============================================================================

# -----------------------------------------------------------------------------
# Sessions Table (Global Table)
# -----------------------------------------------------------------------------
# Used for session storage, cache, and real-time data that needs
# low-latency access from any region.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "sessions" {
  name         = "${local.name_prefix}-sessions"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "pk"
  range_key    = "sk"

  # Only set capacity if PROVISIONED
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "gsi1pk"
    type = "S"
  }

  attribute {
    name = "gsi1sk"
    type = "S"
  }

  # GSI for querying by user or session type
  global_secondary_index {
    name            = "GSI1"
    hash_key        = "gsi1pk"
    range_key       = "gsi1sk"
    projection_type = "ALL"

    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # TTL for automatic session expiration
  ttl {
    enabled        = var.dynamodb_ttl_enabled
    attribute_name = var.dynamodb_ttl_attribute
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  # Stream for DynamoDB Streams (needed for Global Tables v2)
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Global Table replicas (automatically creates in each region)
  dynamic "replica" {
    for_each = {
      for key, region in local.enabled_regions : key => region
      if !region.is_primary
    }
    content {
      region_name            = replica.value.aws_region
      point_in_time_recovery = var.dynamodb_point_in_time_recovery
    }
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-sessions"
    Type = "sessions"
  })

  lifecycle {
    ignore_changes = [replica]
  }
}

# -----------------------------------------------------------------------------
# Orders Table (Global Table)
# -----------------------------------------------------------------------------
# Used for order data that needs global replication for consistency
# across regions.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "orders" {
  name         = "${local.name_prefix}-orders"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "pk"
  range_key    = "sk"

  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "customerId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  attribute {
    name = "entityType"
    type = "S"
  }

  # GSI for querying orders by customer
  global_secondary_index {
    name            = "CustomerOrders"
    hash_key        = "customerId"
    range_key       = "createdAt"
    projection_type = "ALL"

    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # GSI for querying orders by status
  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"

    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # GSI for listing all orders without a full table scan
  global_secondary_index {
    name            = "AllOrders"
    hash_key        = "entityType"
    range_key       = "createdAt"
    projection_type = "ALL"

    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  dynamic "replica" {
    for_each = {
      for key, region in local.enabled_regions : key => region
      if !region.is_primary
    }
    content {
      region_name            = replica.value.aws_region
      point_in_time_recovery = var.dynamodb_point_in_time_recovery
    }
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-orders"
    Type = "orders"
  })

  lifecycle {
    ignore_changes = [replica]
  }
}

# -----------------------------------------------------------------------------
# Events Table (Global Table)
# -----------------------------------------------------------------------------
# Event sourcing table for audit trail and event replay.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "events" {
  name         = "${local.name_prefix}-events"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "pk"
  range_key    = "sk"

  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "eventType"
    type = "S"
  }

  # GSI for querying events by type
  global_secondary_index {
    name            = "EventTypeIndex"
    hash_key        = "eventType"
    range_key       = "sk"
    projection_type = "ALL"

    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  dynamic "replica" {
    for_each = {
      for key, region in local.enabled_regions : key => region
      if !region.is_primary
    }
    content {
      region_name            = replica.value.aws_region
      point_in_time_recovery = var.dynamodb_point_in_time_recovery
    }
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-events"
    Type = "events"
  })

  lifecycle {
    ignore_changes = [replica]
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling (if PROVISIONED billing mode)
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "sessions_read" {
  count = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = var.dynamodb_read_capacity * 10
  min_capacity       = var.dynamodb_read_capacity
  resource_id        = "table/${aws_dynamodb_table.sessions.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "sessions_read" {
  count = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  name               = "${local.name_prefix}-sessions-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sessions_read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.sessions_read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.sessions_read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "sessions_write" {
  count = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = var.dynamodb_write_capacity * 10
  min_capacity       = var.dynamodb_write_capacity
  resource_id        = "table/${aws_dynamodb_table.sessions.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "sessions_write" {
  count = var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  name               = "${local.name_prefix}-sessions-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sessions_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.sessions_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.sessions_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
  }
}
