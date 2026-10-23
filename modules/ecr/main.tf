locals {
  repository_name = join("/", compact([var.namespace, var.name]))
  kms_key_arn     = var.create_kms_key ? module.kms[0].kms_key_arn : var.kms_key_arn

  pull_principals = [for id in var.pull_account_ids : "arn:aws:iam::${id}:root"]

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the latest ${var.max_tagged_images} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

module "kms" {
  count  = var.create_kms_key ? 1 : 0
  source = "../kms"

  name        = "ecr-${replace(local.repository_name, "/", "-")}"
  description = "Encrypts the images of the ECR repository ${local.repository_name}"
  tags        = var.tags
}

resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = var.mutable_image_tags ? "MUTABLE" : "IMMUTABLE"
  force_delete         = var.force_delete
  tags                 = merge(var.tags, { Name = local.repository_name })

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.kms_key_arn
  }

  lifecycle {
    precondition {
      condition     = var.create_kms_key || var.kms_key_arn != null
      error_message = "kms_key_arn is required when create_kms_key is false."
    }
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = var.enable_lifecycle_policy ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository_policy" "pull" {
  count = length(var.pull_account_ids) > 0 ? 1 : 0

  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PullFromListedAccounts"
      Effect    = "Allow"
      Principal = { AWS = local.pull_principals }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    }]
  })
}
