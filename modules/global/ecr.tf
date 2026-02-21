# =============================================================================
# Amazon ECR (Elastic Container Registry)
# =============================================================================
# Manages container image repositories for the multi-region infrastructure.
# ECR is regional but we create repositories in the primary region and use
# cross-region replication for disaster recovery.
# =============================================================================

# -----------------------------------------------------------------------------
# ECR Repositories
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "main" {
  for_each = toset(var.ecr_repositories)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = var.ecr_kms_key_arn != "" ? "KMS" : "AES256"
    kms_key         = var.ecr_kms_key_arn != "" ? var.ecr_kms_key_arn : null
  }

  tags = merge(local.common_tags, var.tags, {
    Name       = "${var.project_name}-${each.value}"
    Repository = each.value
  })
}

# -----------------------------------------------------------------------------
# ECR Lifecycle Policy
# -----------------------------------------------------------------------------
# Automatically clean up old images to reduce storage costs
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "main" {
  for_each = toset(var.ecr_repositories)

  repository = aws_ecr_repository.main[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_lifecycle_policy_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "prod", "staging"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_lifecycle_policy_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Keep last 10 dev images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev", "develop", "feature"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECR Repository Policy
# -----------------------------------------------------------------------------
# Allow cross-account access if needed for CI/CD pipelines
# -----------------------------------------------------------------------------

resource "aws_ecr_repository_policy" "main" {
  for_each = toset(var.ecr_repositories)

  repository = aws_ecr_repository.main[each.value].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
      },
      {
        Sid    = "AllowLambdaPull"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Condition = {
          StringLike = {
            "aws:sourceArn" = "arn:${data.aws_partition.current.partition}:lambda:*:${data.aws_caller_identity.current.account_id}:function:*"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECR Replication Configuration
# -----------------------------------------------------------------------------
# Replicate images to secondary regions for disaster recovery
# Note: This requires ECR replication to be enabled in the AWS account
# -----------------------------------------------------------------------------

resource "aws_ecr_replication_configuration" "main" {
  count = length(local.enabled_regions) > 1 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = {
          for key, region in local.enabled_regions : key => region
          if !region.is_primary
        }

        content {
          region      = destination.value.aws_region
          registry_id = data.aws_caller_identity.current.account_id
        }
      }

      repository_filter {
        filter      = "${var.project_name}/"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# -----------------------------------------------------------------------------
# ECR Pull Through Cache (Optional)
# -----------------------------------------------------------------------------
# Cache public container images from Docker Hub, GitHub, etc.
# Reduces external dependencies and improves pull times
# -----------------------------------------------------------------------------

# resource "aws_ecr_pull_through_cache_rule" "dockerhub" {
#   ecr_repository_prefix = "dockerhub"
#   upstream_registry_url = "registry-1.docker.io"
# }

# resource "aws_ecr_pull_through_cache_rule" "ghcr" {
#   ecr_repository_prefix = "ghcr"
#   upstream_registry_url = "ghcr.io"
# }
