locals {
  full_name       = join("-", compact([var.name, var.environment, var.name_suffix]))
  in_vpc          = length(var.subnet_ids) > 0
  handler_dir     = split(".", var.handler)[0]
  has_environment = length(var.environment_variables) > 0
}

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/.terraform/placeholder-${local.full_name}.zip"

  source {
    content  = "exports.handler = async () => ({ statusCode: 503 });\n"
    filename = "${local.handler_dir}.cjs"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.full_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  dynamic "statement" {
    for_each = local.has_environment && var.kms_key_arn != null ? [var.kms_key_arn] : []

    content {
      sid       = "DecryptEnvironment"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }

  dynamic "statement" {
    for_each = { for statement in var.policy_statements : statement.sid => statement }

    content {
      sid       = statement.value.sid
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.full_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "this" {
  name   = "function"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  count = local.in_vpc ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name = local.full_name
  role          = aws_iam_role.this.arn
  runtime       = var.runtime
  handler       = var.handler
  architectures = var.architectures
  timeout       = var.timeout
  memory_size   = var.memory_size
  kms_key_arn   = local.has_environment ? var.kms_key_arn : null
  tags          = merge(var.tags, { Name = local.full_name })

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  dynamic "vpc_config" {
    for_each = local.in_vpc ? [1] : []

    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  dynamic "environment" {
    for_each = local.has_environment ? [1] : []

    content {
      variables = var.environment_variables
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]

    precondition {
      condition     = !local.has_environment || var.kms_key_arn != null
      error_message = "kms_key_arn is required when environment_variables is not empty, so environment values are never stored under the default key."
    }
  }

  depends_on = [aws_iam_role_policy.this, aws_iam_role_policy_attachment.vpc_access]
}
