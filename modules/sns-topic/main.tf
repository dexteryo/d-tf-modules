data "aws_caller_identity" "current" {}

locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))

  cloudwatch_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudWatchAlarmsPublish"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.this.arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_sns_topic" "this" {
  name              = local.full_name
  display_name      = local.full_name
  kms_master_key_id = var.kms_key_arn
  tags              = merge(var.tags, { Name = local.full_name })
}

resource "aws_sns_topic_policy" "cloudwatch_alarms" {
  count = var.allow_cloudwatch_alarms ? 1 : 0

  arn    = aws_sns_topic.this.arn
  policy = local.cloudwatch_policy
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.email_addresses)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "https" {
  for_each = toset(var.https_endpoints)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "https"
  endpoint  = each.value
}
