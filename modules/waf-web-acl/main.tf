locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))

  rate_rule_priority = max(concat([0], [for group in var.managed_rule_groups : group.priority])...) + 10
  rate_rule_enabled  = var.rate_limit_per_5_minutes != null
}

resource "aws_wafv2_web_acl" "this" {
  name  = local.full_name
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = var.managed_rule_groups

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = rule.value.vendor_name
          name        = rule.value.name
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.full_name}-${rule.value.name}"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.rate_rule_enabled ? [var.rate_limit_per_5_minutes] : []

    content {
      name     = "rate-limit-per-ip"
      priority = local.rate_rule_priority

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = rule.value
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.full_name}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.full_name
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.full_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "aws-waf-logs-${local.full_name}" })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  dynamic "redacted_fields" {
    for_each = var.redacted_headers

    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }

  dynamic "redacted_fields" {
    for_each = var.redact_uri_path ? [1] : []

    content {
      uri_path {}
    }
  }

  dynamic "redacted_fields" {
    for_each = var.redact_query_string ? [1] : []

    content {
      query_string {}
    }
  }
}
