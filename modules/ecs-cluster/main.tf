locals {
  full_name = "${var.name}-${var.environment}"
  tags      = merge(var.tags, { Name = local.full_name })
}

resource "aws_cloudwatch_log_group" "execute_command" {
  count = var.enable_execute_command_logging ? 1 : 0

  name              = "/ecs/${local.full_name}/execute-command"
  retention_in_days = var.execute_command_log_retention_days
  kms_key_id        = var.execute_command_log_kms_key_arn
  tags              = local.tags
}

resource "aws_ecs_cluster" "this" {
  name = local.full_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  dynamic "configuration" {
    for_each = var.enable_execute_command_logging ? [1] : []

    content {
      execute_command_configuration {
        kms_key_id = var.execute_command_kms_key_arn
        logging    = "OVERRIDE"

        log_configuration {
          cloud_watch_encryption_enabled = var.execute_command_log_kms_key_arn != null
          cloud_watch_log_group_name     = aws_cloudwatch_log_group.execute_command[0].name
        }
      }
    }
  }

  tags = local.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy

    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}
