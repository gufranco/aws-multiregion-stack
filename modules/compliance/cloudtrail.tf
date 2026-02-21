# =============================================================================
# AWS CloudTrail
# =============================================================================
# Audit logging for AWS API calls.
# =============================================================================

# -----------------------------------------------------------------------------
# CloudTrail S3 Bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail && var.cloudtrail_s3_bucket_name == "" ? 1 : 0

  bucket = "${local.name_prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-cloudtrail"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.enable_cloudtrail && var.cloudtrail_s3_bucket_name == "" ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.enable_cloudtrail && var.cloudtrail_s3_bucket_name == "" ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.cloudtrail_kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.cloudtrail_kms_key_arn != "" ? var.cloudtrail_kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.enable_cloudtrail && var.cloudtrail_s3_bucket_name == "" ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = var.s3_archive_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_archive_days + 365
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail && var.cloudtrail_s3_bucket_name == "" ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudTrail
# -----------------------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = var.cloudtrail_s3_bucket_name != "" ? var.cloudtrail_s3_bucket_name : aws_s3_bucket.cloudtrail[0].id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.cloudtrail_kms_key_arn != "" ? var.cloudtrail_kms_key_arn : null

  # Data events for S3 and DynamoDB
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  event_selector {
    read_write_type           = "All"
    include_management_events = false

    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = ["arn:aws:dynamodb"]
    }
  }

  # CloudTrail Insights
  dynamic "insight_selector" {
    for_each = var.cloudtrail_enable_insights ? [1] : []
    content {
      insight_type = "ApiCallRateInsight"
    }
  }

  dynamic "insight_selector" {
    for_each = var.cloudtrail_enable_insights ? [1] : []
    content {
      insight_type = "ApiErrorRateInsight"
    }
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-trail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
