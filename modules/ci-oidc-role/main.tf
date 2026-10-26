locals {
  full_name          = join("-", compact([var.name, var.environment, var.name_suffix]))
  github_environment = coalesce(var.github_environment, var.environment)
  repository_claim = var.github_immutable_ids == null ? var.github_repository : format(
    "%s@%d/%s@%d",
    split("/", var.github_repository)[0], var.github_immutable_ids.owner_id,
    split("/", var.github_repository)[1], var.github_immutable_ids.repository_id,
  )
  subject       = "repo:${local.repository_claim}:environment:${local.github_environment}"
  provider_host = "token.actions.githubusercontent.com"
  provider_arn  = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn

  statements = concat(
    [{
      Sid      = "EcrAuthorisationToken"
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = ["*"]
    }],
    length(var.ecr_repository_arns) == 0 ? [] : [{
      Sid    = "PushAndReadImages"
      Effect = "Allow"
      Action = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      Resource = var.ecr_repository_arns
    }],
    length(var.ecs_service_arns) == 0 ? [] : [
      {
        Sid      = "TaskDefinitions"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = ["*"]
      },
      {
        Sid      = "DeployServices"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:UpdateService"]
        Resource = var.ecs_service_arns
      },
    ],
    length(var.pass_role_arns) == 0 ? [] : [{
      Sid       = "PassTaskRolesToEcs"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = var.pass_role_arns
      Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
    }],
    length(var.static_site_bucket_arns) == 0 ? [] : [
      {
        Sid      = "ListStaticSiteBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.static_site_bucket_arns
      },
      {
        Sid      = "WriteStaticSiteObjects"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject", "s3:PutObject"]
        Resource = [for arn in var.static_site_bucket_arns : "${arn}/*"]
      },
    ],
    length(var.static_site_kms_key_arns) == 0 ? [] : [{
      Sid      = "EncryptStaticSiteObjects"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = var.static_site_kms_key_arns
    }],
    length(var.cloudfront_distribution_arns) == 0 ? [] : [{
      Sid      = "InvalidateDistributions"
      Effect   = "Allow"
      Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
      Resource = var.cloudfront_distribution_arns
    }],
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.provider_host}"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

resource "aws_iam_role" "this" {
  name                 = local.full_name
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = merge(var.tags, { Name = local.full_name })

  lifecycle {
    precondition {
      condition     = var.create_oidc_provider || var.oidc_provider_arn != null
      error_message = "oidc_provider_arn is required when create_oidc_provider is false."
    }
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.provider_host}:aud" = "sts.amazonaws.com"
          "${local.provider_host}:sub" = local.subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "deploy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.statements
  })
}
