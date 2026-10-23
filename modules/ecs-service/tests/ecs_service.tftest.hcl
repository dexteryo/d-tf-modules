mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/mock:1"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/mock/0123456789abcdef"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/mock"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "eu-west-1"
    }
  }
}

variables {
  name        = "ordering-agent"
  environment = "integration"
  cluster_arn = "arn:aws:ecs:eu-west-1:123456789012:cluster/example-integration"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]

  security_group_ids = ["sg-0fedcba9876543210"]
  cpu                = 512
  memory             = 1024

  default_health_check_path = "/healthz"

  containers = [
    {
      name  = "agent"
      image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/agent:placeholder"
      port  = 8788
      secrets = {
        API_KEY = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/agent-AbCdEf:api_key::"
        TOKEN   = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/token-GhIjKl"
        DB_URL  = "arn:aws:ssm:eu-west-1:123456789012:parameter/example/db-url"
      }
    },
    {
      name  = "sidecar"
      image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/sidecar:placeholder"
      port  = 8787
      health_check = {
        command = ["CMD-SHELL", "curl -f http://127.0.0.1:8787/ready || exit 1"]
      }
    },
  ]

  load_balancer = {
    container_name = "agent"
    container_port = 8788
    vpc_id         = "vpc-0123456789abcdef0"
    listener_arn   = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/example/0123456789abcdef/0123456789abcdef"
    host_headers   = ["agent.example.com"]
    priority       = 100
  }

  extra_execution_secret_arns = ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/extra-MnOpQr"]
  kms_key_arns                = ["arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"]
}

run "service_ignores_task_definition_changes_first_apply" {
  command = apply

  assert {
    condition     = length(aws_ecs_service.externally_managed) == 1 && length(aws_ecs_service.terraform_managed) == 0
    error_message = "Externally managed service must be the default."
  }
}

run "service_ignores_task_definition_changes_after_new_revision" {
  command = apply

  plan_options {
    replace = [aws_ecs_task_definition.this]
  }

  override_resource {
    target = aws_ecs_task_definition.this
    values = {
      arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/mock:2"
    }
  }

  variables {
    desired_count = 5
    containers = [
      {
        name  = "agent"
        image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/agent:changed"
        port  = 8788
      },
    ]
  }

  assert {
    condition     = aws_ecs_service.externally_managed[0].task_definition == run.service_ignores_task_definition_changes_first_apply.task_definition_arn
    error_message = "The service must keep its deployed task definition when Terraform registers a new revision."
  }

  assert {
    condition     = aws_ecs_service.externally_managed[0].desired_count == 1
    error_message = "The service must keep its current desired count so autoscaling and deploys are not reverted."
  }

  assert {
    condition     = aws_ecs_task_definition.this.arn != run.service_ignores_task_definition_changes_first_apply.task_definition_arn
    error_message = "The test did not produce a new task definition revision."
  }
}

run "terraform_managed_service_follows_task_definition" {
  command = apply

  variables {
    manage_task_definition_externally = false
  }

  assert {
    condition     = length(aws_ecs_service.terraform_managed) == 1 && length(aws_ecs_service.externally_managed) == 0
    error_message = "manage_task_definition_externally = false must use the Terraform-managed service."
  }
}

run "service_uses_the_given_security_groups_and_owns_none" {
  command = apply

  assert {
    condition     = toset(aws_ecs_service.externally_managed[0].network_configuration[0].security_groups) == toset(["sg-0fedcba9876543210"])
    error_message = "The service must attach exactly the security groups it was given."
  }

  assert {
    condition     = aws_ecs_service.externally_managed[0].network_configuration[0].assign_public_ip == false
    error_message = "Tasks must not get a public IP by default."
  }
}

run "target_group_lives_in_the_vpc_of_the_load_balancer" {
  command = apply

  assert {
    condition     = aws_lb_target_group.this[0].vpc_id == "vpc-0123456789abcdef0" && aws_lb_target_group.this[0].port == 8788 && aws_lb_target_group.this[0].target_type == "ip"
    error_message = "The target group must use the given VPC, the container port and ip targets."
  }

  assert {
    condition     = one([for c in aws_lb_listener_rule.this[0].condition : one([for h in c.host_header : one(h.values)]) if length(c.host_header) > 0]) == "agent.example.com"
    error_message = "The listener rule must match the host header."
  }
}

run "target_group_suffix_is_exposed_for_alarms" {
  command = apply

  assert {
    condition     = output.target_group_arn_suffix == aws_lb_target_group.this[0].arn_suffix
    error_message = "The target group suffix output must follow the target group."
  }
}

run "no_target_group_or_rule_without_load_balancer" {
  command = apply

  variables {
    load_balancer = null
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0
    error_message = "Without a load balancer there is no target group or rule."
  }
}

run "rejects_empty_security_group_list" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "execution_role_reads_exactly_the_listed_secrets" {
  command = apply

  assert {
    condition = toset(
      [for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s if s.Sid == "ReadSecretsManagerSecrets"][0].Resource
      ) == toset([
        "arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/agent-AbCdEf",
        "arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/token-GhIjKl",
        "arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/extra-MnOpQr",
    ])
    error_message = "Secrets Manager read access must cover exactly the listed secrets, without the json-key suffix."
  }

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s if s.Sid == "ReadSsmParameters"][0].Resource == [
      "arn:aws:ssm:eu-west-1:123456789012:parameter/example/db-url",
    ]
    error_message = "SSM read access must cover exactly the listed parameter."
  }

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s if s.Sid == "DecryptSecrets"][0].Resource == [
      "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000",
    ]
    error_message = "KMS decrypt must be limited to the listed keys."
  }

  assert {
    condition = toset(
      [for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s if s.Sid == "PullImages"][0].Resource
      ) == toset([
        "arn:aws:ecr:eu-west-1:123456789012:repository/example/agent",
        "arn:aws:ecr:eu-west-1:123456789012:repository/example/sidecar",
    ])
    error_message = "ECR pull must be limited to the repositories of the container images."
  }
}

run "generated_health_checks_use_loopback_address" {
  command = apply

  assert {
    condition     = [for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "agent"][0].healthCheck.command[1] == "curl -fsS http://127.0.0.1:8788/healthz || exit 1"
    error_message = "The generated health check must target 127.0.0.1 and the container port."
  }

  assert {
    condition     = alltrue([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : !strcontains(join(" ", c.healthCheck.command), "localhost")])
    error_message = "Health checks must not use localhost."
  }

  assert {
    condition     = [for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c if c.name == "sidecar"][0].healthCheck.command[1] == "curl -f http://127.0.0.1:8787/ready || exit 1"
    error_message = "An explicit health check must be kept as given."
  }
}

run "no_wildcard_resource_except_ecr_token" {
  command = apply

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.execution.policy).Statement :
      !contains(s.Resource, "*") || s.Action == ["ecr:GetAuthorizationToken"]
    ])
    error_message = "Only ecr:GetAuthorizationToken may use Resource *."
  }

  assert {
    condition     = length(aws_iam_role_policy.task_execute_command) == 0
    error_message = "ECS Exec permissions must be off by default."
  }
}

run "task_role_is_scoped_to_the_account" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.task.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "The task role trust policy must pin aws:SourceAccount."
  }

  assert {
    condition     = jsondecode(aws_iam_role.task.assume_role_policy).Statement[0].Principal.Service == "ecs-tasks.amazonaws.com"
    error_message = "The task role must be assumable by ecs-tasks only."
  }
}

run "read_only_root_filesystem_defaults_to_true" {
  command = apply

  assert {
    condition     = alltrue([for c in jsondecode(aws_ecs_task_definition.this.container_definitions) : c.readonlyRootFilesystem])
    error_message = "readonlyRootFilesystem must default to true."
  }
}

run "log_driver_uses_container_name_as_stream_prefix" {
  command = apply

  assert {
    condition = alltrue([
      for c in jsondecode(aws_ecs_task_definition.this.container_definitions) :
      c.logConfiguration.options["awslogs-stream-prefix"] == c.name
    ])
    error_message = "The awslogs stream prefix must equal the container name."
  }
}

run "rejects_duplicate_container_names" {
  command = plan

  variables {
    containers = [
      { name = "a", image = "example/a:1" },
      { name = "a", image = "example/b:1" },
    ]
    load_balancer = null
  }

  expect_failures = [var.containers]
}

run "execute_command_wildcard_is_limited_to_the_session_channels" {
  command = apply

  variables {
    enable_execute_command = true
  }

  assert {
    condition     = alltrue([for a in jsondecode(aws_iam_role_policy.task_execute_command[0].policy).Statement[0].Action : startswith(a, "ssmmessages:")])
    error_message = "The only wildcard resource of the task role may belong to the ssmmessages session channel actions."
  }

  assert {
    condition     = aws_ecs_service.externally_managed[0].enable_execute_command
    error_message = "The service must enable ECS Exec."
  }
}

run "application_policy_is_attached_only_when_given" {
  command = apply

  assert {
    condition     = length(aws_iam_role_policy.task) == 0
    error_message = "The task role has no permissions unless a policy is passed."
  }
}
