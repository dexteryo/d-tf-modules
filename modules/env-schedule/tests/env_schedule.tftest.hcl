mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/ordering-integration-scheduler"
    }
  }
}

variables {
  name          = "ordering"
  environment   = "integration"
  tags          = { Environment = "integration" }
  timezone      = "Europe/Dublin"
  stop_schedule = "cron(0 20 ? * MON-FRI *)"
  ecs_services = {
    api = {
      cluster_name  = "ordering-integration"
      service_name  = "ordering-api-integration"
      desired_count = 2
    }
  }
  db_instances = {
    main = "ordering-integration-postgres"
  }
}

run "group_and_schedules_are_named_from_the_inputs" {
  command = apply

  assert {
    condition     = aws_scheduler_schedule_group.this.name == "ordering-integration" && aws_scheduler_schedule_group.this.tags["Environment"] == "integration"
    error_message = "The group is named <name>-<environment> and tagged."
  }

  assert {
    condition = (
      aws_scheduler_schedule.stop_database["main"].name == "ordering-integration-stop-db-main" &&
      aws_scheduler_schedule.start_database["main"].name == "ordering-integration-start-db-main" &&
      aws_scheduler_schedule.stop_service["api"].name == "ordering-integration-stop-svc-api" &&
      aws_scheduler_schedule.start_service["api"].name == "ordering-integration-start-svc-api"
    )
    error_message = "Schedules are named <group>-<stop|start>-<db|svc>-<key>, which the operator workflow relies on."
  }

  assert {
    condition     = alltrue([for schedule in concat(values(aws_scheduler_schedule.stop_database), values(aws_scheduler_schedule.stop_service), values(aws_scheduler_schedule.start_database), values(aws_scheduler_schedule.start_service)) : schedule.group_name == "ordering-integration" && schedule.schedule_expression_timezone == "Europe/Dublin"])
    error_message = "Every schedule must sit in the group and read its cron in the given time zone."
  }
}

run "stop_scales_services_to_zero_and_stops_databases" {
  command = apply

  assert {
    condition     = aws_scheduler_schedule.stop_service["api"].schedule_expression == var.stop_schedule && aws_scheduler_schedule.stop_database["main"].schedule_expression == var.stop_schedule
    error_message = "Services and databases stop on stop_schedule."
  }

  assert {
    condition     = aws_scheduler_schedule.stop_service["api"].target[0].arn == "arn:aws:scheduler:::aws-sdk:ecs:updateService" && jsondecode(aws_scheduler_schedule.stop_service["api"].target[0].input) == { Cluster = "ordering-integration", Service = "ordering-api-integration", DesiredCount = 0 }
    error_message = "The stop schedule must set the service's desired count to zero."
  }

  assert {
    condition     = aws_scheduler_schedule.stop_database["main"].target[0].arn == "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance" && jsondecode(aws_scheduler_schedule.stop_database["main"].target[0].input) == { DbInstanceIdentifier = "ordering-integration-postgres" }
    error_message = "The stop schedule must stop the DB instance."
  }

  assert {
    condition     = aws_scheduler_schedule.stop_service["api"].state == "ENABLED" && aws_scheduler_schedule.stop_database["main"].state == "ENABLED"
    error_message = "Stop schedules are always enabled."
  }
}

run "without_start_schedule_the_start_schedules_exist_disabled" {
  command = apply

  assert {
    condition     = aws_scheduler_schedule.start_service["api"].state == "DISABLED" && aws_scheduler_schedule.start_database["main"].state == "DISABLED"
    error_message = "With no start_schedule the environment must only start when an operator starts it."
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.start_service["api"].target[0].input).DesiredCount == 2 && aws_scheduler_schedule.start_database["main"].target[0].arn == "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    error_message = "Disabled start schedules still carry the targets the operator workflow replays."
  }
}

run "start_schedule_starts_databases_before_services" {
  command = apply

  variables {
    start_schedule = {
      databases = "cron(40 7 ? * MON-FRI *)"
      services  = "cron(55 7 ? * MON-FRI *)"
    }
  }

  assert {
    condition     = aws_scheduler_schedule.start_database["main"].state == "ENABLED" && aws_scheduler_schedule.start_database["main"].schedule_expression == "cron(40 7 ? * MON-FRI *)"
    error_message = "Databases start on start_schedule.databases."
  }

  assert {
    condition     = aws_scheduler_schedule.start_service["api"].state == "ENABLED" && aws_scheduler_schedule.start_service["api"].schedule_expression == "cron(55 7 ? * MON-FRI *)"
    error_message = "Services start on start_schedule.services."
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.start_service["api"].target[0].input) == { Cluster = "ordering-integration", Service = "ordering-api-integration", DesiredCount = 2 }
    error_message = "The start restores the configured desired count."
  }
}

run "scheduler_role_trusts_only_scheduler_in_this_account" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.scheduler.assume_role_policy).Statement[0].Principal == { Service = "scheduler.amazonaws.com" }
    error_message = "Only EventBridge Scheduler may assume the scheduler role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.scheduler.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "The trust must be limited to this account (confused deputy protection)."
  }
}

run "scheduler_policy_names_each_target_exactly" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role_policy.scheduler.policy).Statement == [
      {
        Sid      = "StopAndStartDatabases"
        Effect   = "Allow"
        Action   = ["rds:StartDBInstance", "rds:StopDBInstance"]
        Resource = ["arn:aws:rds:eu-west-1:123456789012:db:ordering-integration-postgres"]
      },
      {
        Sid      = "ScaleServices"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = ["arn:aws:ecs:eu-west-1:123456789012:service/ordering-integration/ordering-api-integration"]
      },
    ]
    error_message = "The scheduler may only start and stop the given databases and update the given services."
  }
}

run "services_only_leaves_out_database_permissions" {
  command = apply

  variables {
    db_instances = {}
  }

  assert {
    condition     = length(aws_scheduler_schedule.stop_database) == 0 && length(jsondecode(aws_iam_role_policy.scheduler.policy).Statement) == 1
    error_message = "Without databases there are no database schedules and no RDS permissions."
  }
}

run "no_operator_role_by_default" {
  command = apply

  assert {
    condition     = length(aws_iam_role.operator) == 0 && output.operator_role_arn == null
    error_message = "No operator role unless operator is set."
  }
}

run "operator_role_trusts_one_repository_environment" {
  command = apply

  variables {
    operator = {
      github_repository  = "example-org/example-app"
      github_environment = "integration"
      oidc_provider_arn  = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.operator[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/example-app:environment:integration"
    error_message = "The operator role must trust exactly one repository environment."
  }

  assert {
    condition     = jsondecode(aws_iam_role.operator[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The operator role must require the STS audience."
  }

  assert {
    condition = (
      contains([for statement in jsondecode(aws_iam_role_policy.operator[0].policy).Statement : statement.Sid], "StopAndStartDatabases") &&
      contains([for statement in jsondecode(aws_iam_role_policy.operator[0].policy).Statement : statement.Sid], "ScaleServices") &&
      one([for statement in jsondecode(aws_iam_role_policy.operator[0].policy).Statement : statement.Resource if statement.Sid == "ReadSchedules"]) == "arn:aws:scheduler:eu-west-1:123456789012:schedule/ordering-integration/*"
    )
    error_message = "The operator may act on the same targets and read only this group's schedules."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.operator[0].policy).Statement : statement.Resource != "*" if statement.Sid != "ListSchedules"])
    error_message = "Only ListSchedules, which has no resource-level permissions, may use a wildcard resource."
  }
}

run "operator_role_supports_immutable_subject_claims" {
  command = apply

  variables {
    operator = {
      github_repository    = "example-org/example-app"
      github_environment   = "integration"
      oidc_provider_arn    = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      github_immutable_ids = { owner_id = 111, repository_id = 222 }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.operator[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org@111/example-app@222:environment:integration"
    error_message = "With immutable IDs the subject must use owner@id/name@id."
  }
}

run "no_targets_is_refused" {
  command = plan

  variables {
    ecs_services = {}
    db_instances = {}
  }

  expect_failures = [aws_scheduler_schedule_group.this]
}

run "rate_expression_is_refused" {
  command = plan

  variables {
    stop_schedule = "rate(1 day)"
  }

  expect_failures = [var.stop_schedule]
}

run "start_schedule_must_be_cron" {
  command = plan

  variables {
    start_schedule = {
      databases = "cron(40 7 ? * MON-FRI *)"
      services  = "at(2030-01-01T08:00:00)"
    }
  }

  expect_failures = [var.start_schedule]
}

run "zero_desired_count_is_refused" {
  command = plan

  variables {
    ecs_services = {
      api = {
        cluster_name  = "ordering-integration"
        service_name  = "ordering-api-integration"
        desired_count = 0
      }
    }
  }

  expect_failures = [var.ecs_services]
}

run "long_key_is_refused" {
  command = plan

  variables {
    db_instances = {
      "a-key-that-is-far-too-long" = "ordering-integration-postgres"
    }
  }

  expect_failures = [var.db_instances]
}

run "wildcard_operator_repository_is_refused" {
  command = plan

  variables {
    operator = {
      github_repository  = "example-org/*"
      github_environment = "integration"
      oidc_provider_arn  = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  expect_failures = [var.operator]
}

run "invalid_timezone_is_refused" {
  command = plan

  variables {
    timezone = "GMT+7"
  }

  expect_failures = [var.timezone]
}
