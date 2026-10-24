locals {
  access_logs_enabled = var.access_logs != null

  access_log_fields = [
    "timestamp",
    "DistributionId",
    "date",
    "time",
    "x-edge-location",
    "sc-bytes",
    "c-ip",
    "cs-method",
    "cs(Host)",
    "cs-uri-stem",
    "sc-status",
    "cs(User-Agent)",
    "x-edge-result-type",
    "x-edge-request-id",
    "cs-protocol",
    "time-taken",
  ]
}

resource "aws_cloudwatch_log_group" "access" {
  count = local.access_logs_enabled ? 1 : 0

  name              = "/aws/cloudfront/${local.full_name}"
  retention_in_days = var.access_logs.retention_days
  kms_key_id        = var.access_logs.kms_key_arn

  tags = merge(var.tags, { Name = "/aws/cloudfront/${local.full_name}" })
}

resource "aws_cloudwatch_log_delivery_source" "access" {
  count = local.access_logs_enabled ? 1 : 0

  name         = local.full_name
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this.arn

  tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_cloudwatch_log_delivery_destination" "access" {
  count = local.access_logs_enabled ? 1 : 0

  name          = local.full_name
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.access[0].arn
  }

  tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_cloudwatch_log_delivery" "access" {
  count = local.access_logs_enabled ? 1 : 0

  delivery_source_name     = aws_cloudwatch_log_delivery_source.access[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.access[0].arn
  record_fields            = local.access_log_fields

  tags = merge(var.tags, { Name = local.full_name })
}
