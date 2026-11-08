data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  full_name  = "${var.name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  disabled_start_expression = "cron(0 0 1 1 ? *)"

  database_arns = [for identifier in values(var.db_instances) : "arn:aws:rds:${local.region}:${local.account_id}:db:${identifier}"]
  service_arns  = [for service in values(var.ecs_services) : "arn:aws:ecs:${local.region}:${local.account_id}:service/${service.cluster_name}/${service.service_name}"]

  target_statements = concat(
    length(local.database_arns) == 0 ? [] : [{
      Sid      = "StopAndStartDatabases"
      Effect   = "Allow"
      Action   = ["rds:StartDBInstance", "rds:StopDBInstance"]
      Resource = local.database_arns
    }],
    length(local.service_arns) == 0 ? [] : [{
      Sid      = "ScaleServices"
      Effect   = "Allow"
      Action   = ["ecs:UpdateService"]
      Resource = local.service_arns
    }],
  )
}

resource "aws_scheduler_schedule_group" "this" {
  name = local.full_name
  tags = merge(var.tags, { Name = local.full_name })

  lifecycle {
    precondition {
      condition     = length(var.ecs_services) + length(var.db_instances) > 0
      error_message = "At least one of ecs_services or db_instances must be set."
    }
  }
}

resource "aws_scheduler_schedule" "stop_database" {
  for_each = var.db_instances

  name                         = "${local.full_name}-stop-db-${each.key}"
  group_name                   = aws_scheduler_schedule_group.this.name
  state                        = "ENABLED"
  schedule_expression          = var.stop_schedule
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbInstanceIdentifier = each.value })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}

resource "aws_scheduler_schedule" "start_database" {
  for_each = var.db_instances

  name                         = "${local.full_name}-start-db-${each.key}"
  group_name                   = aws_scheduler_schedule_group.this.name
  state                        = var.start_schedule == null ? "DISABLED" : "ENABLED"
  schedule_expression          = var.start_schedule == null ? local.disabled_start_expression : var.start_schedule.databases
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbInstanceIdentifier = each.value })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}

resource "aws_scheduler_schedule" "stop_service" {
  for_each = var.ecs_services

  name                         = "${local.full_name}-stop-svc-${each.key}"
  group_name                   = aws_scheduler_schedule_group.this.name
  state                        = "ENABLED"
  schedule_expression          = var.stop_schedule
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ Cluster = each.value.cluster_name, Service = each.value.service_name, DesiredCount = 0 })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}

resource "aws_scheduler_schedule" "start_service" {
  for_each = var.ecs_services

  name                         = "${local.full_name}-start-svc-${each.key}"
  group_name                   = aws_scheduler_schedule_group.this.name
  state                        = var.start_schedule == null ? "DISABLED" : "ENABLED"
  schedule_expression          = var.start_schedule == null ? local.disabled_start_expression : var.start_schedule.services
  schedule_expression_timezone = var.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ Cluster = each.value.cluster_name, Service = each.value.service_name, DesiredCount = each.value.desired_count })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}
