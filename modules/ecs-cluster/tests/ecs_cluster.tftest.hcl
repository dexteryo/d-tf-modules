mock_provider "aws" {}

variables {
  name        = "ordering"
  environment = "integration"
  tags        = { Environment = "integration", Service = "ordering" }
}

run "container_insights_on_and_both_fargate_providers" {
  command = apply

  assert {
    condition     = [for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"][0] == "enabled"
    error_message = "Container Insights must be enabled by default."
  }

  assert {
    condition     = toset(aws_ecs_cluster_capacity_providers.this.capacity_providers) == toset(["FARGATE", "FARGATE_SPOT"])
    error_message = "Both FARGATE and FARGATE_SPOT must be registered."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.execute_command) == 0
    error_message = "Execute command logging is off by default."
  }
}

run "cluster_is_named_from_the_inputs_and_carries_the_tags" {
  command = apply

  assert {
    condition     = aws_ecs_cluster.this.name == "ordering-integration" && output.cluster_name == "ordering-integration"
    error_message = "The cluster is named <name>-<environment>."
  }

  assert {
    condition     = aws_ecs_cluster.this.tags["Service"] == "ordering" && aws_ecs_cluster.this.tags["Name"] == "ordering-integration"
    error_message = "Tags from the tags input and the Name tag must be applied."
  }
}

run "default_strategy_runs_tasks_on_fargate" {
  command = apply

  assert {
    condition     = [for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : s.capacity_provider] == ["FARGATE"]
    error_message = "Services without their own strategy must run on FARGATE."
  }
}

run "execute_command_logging_is_encrypted" {
  command = apply

  variables {
    enable_execute_command_logging  = true
    execute_command_kms_key_arn     = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    execute_command_log_kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = aws_cloudwatch_log_group.execute_command[0].kms_key_id == var.execute_command_log_kms_key_arn
    error_message = "The execute command log group must use the given KMS key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.execute_command[0].name == "/ecs/ordering-integration/execute-command"
    error_message = "The log group is named from the cluster name."
  }

  assert {
    condition     = aws_ecs_cluster.this.configuration[0].execute_command_configuration[0].log_configuration[0].cloud_watch_encryption_enabled
    error_message = "CloudWatch encryption must be enabled when a log key is given."
  }
}

run "rejects_unknown_capacity_providers" {
  command = plan

  variables {
    default_capacity_provider_strategy = [{ capacity_provider = "EC2", weight = 1 }]
  }

  expect_failures = [var.default_capacity_provider_strategy]
}
