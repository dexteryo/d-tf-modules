locals {
  operator_repository_claim = var.operator == null ? null : (
    var.operator.github_immutable_ids == null ? var.operator.github_repository : format(
      "%s@%d/%s@%d",
      split("/", var.operator.github_repository)[0], var.operator.github_immutable_ids.owner_id,
      split("/", var.operator.github_repository)[1], var.operator.github_immutable_ids.repository_id,
    )
  )
  operator_subject = var.operator == null ? null : "repo:${local.operator_repository_claim}:environment:${var.operator.github_environment}"

  operator_read_statements = concat(
    [
      {
        Sid      = "ListSchedules"
        Effect   = "Allow"
        Action   = ["scheduler:ListSchedules"]
        Resource = "*"
      },
      {
        Sid      = "ReadSchedules"
        Effect   = "Allow"
        Action   = ["scheduler:GetSchedule"]
        Resource = "arn:aws:scheduler:${local.region}:${local.account_id}:schedule/${local.full_name}/*"
      },
    ],
    length(local.database_arns) == 0 ? [] : [{
      Sid      = "DescribeDatabases"
      Effect   = "Allow"
      Action   = ["rds:DescribeDBInstances"]
      Resource = local.database_arns
    }],
    length(local.service_arns) == 0 ? [] : [{
      Sid      = "DescribeServices"
      Effect   = "Allow"
      Action   = ["ecs:DescribeServices"]
      Resource = local.service_arns
    }],
  )
}

resource "aws_iam_role" "scheduler" {
  name = "${local.full_name}-scheduler"
  tags = merge(var.tags, { Name = "${local.full_name}-scheduler" })

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "targets"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.target_statements
  })
}

resource "aws_iam_role" "operator" {
  count = var.operator == null ? 0 : 1

  name = "${local.full_name}-operator"
  tags = merge(var.tags, { Name = "${local.full_name}-operator" })

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.operator.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.operator_subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "operator" {
  count = var.operator == null ? 0 : 1

  name = "operate"
  role = aws_iam_role.operator[0].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.target_statements, local.operator_read_statements)
  })
}
