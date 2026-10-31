mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/ordering-integration-intake"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/ordering-integration-intake-lambda"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:eu-west-1:123456789012:function:ordering-integration-intake"
      invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:ordering-integration-intake/invocations"
    }
  }
}

variables {
  name             = "ordering"
  environment      = "integration"
  name_suffix      = "intake"
  tags             = { Environment = "integration" }
  runtime          = "nodejs22.x"
  handler          = "intake.handler"
  kms_key_arn      = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  logs_kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-1111-1111-1111-111111111111"
}

run "the_function_is_named_encrypted_and_logs_json" {
  command = apply

  assert {
    condition     = aws_lambda_function.this.function_name == "ordering-integration-intake" && aws_iam_role.this.name == "ordering-integration-intake-lambda"
    error_message = "The function is named <name>-<environment>-<name_suffix> and its role adds -lambda."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == var.kms_key_arn && aws_cloudwatch_log_group.this.kms_key_id == var.logs_kms_key_arn
    error_message = "Environment variables and logs must use the given keys."
  }

  assert {
    condition     = one(aws_lambda_function.this.logging_config).log_format == "JSON" && aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "Logs are JSON and kept for a year by default."
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["arm64"]) && aws_lambda_function.this.tags["Environment"] == "integration"
    error_message = "The default architecture is arm64 and tags must be applied."
  }
}

run "the_first_apply_ships_a_placeholder_named_after_the_handler" {
  command = apply

  assert {
    condition     = strcontains(data.archive_file.placeholder.output_path, "placeholder-ordering-integration-intake.zip")
    error_message = "Without filename the module builds a placeholder zip."
  }

  assert {
    condition     = one(data.archive_file.placeholder.source).filename == "intake.cjs"
    error_message = "The placeholder file is named after the handler's file so the handler resolves."
  }
}

run "outside_a_vpc_by_default" {
  command = apply

  assert {
    condition     = length(aws_iam_role_policy_attachment.vpc_access) == 0 && length(aws_lambda_function.this.vpc_config) == 0
    error_message = "Without subnets the function runs outside a VPC and needs no network policy."
  }
}

run "in_a_vpc_when_subnets_are_given" {
  command = apply

  variables {
    subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.vpc_access) == 1 && one(aws_lambda_function.this.vpc_config).security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "Subnets and security groups attach the function to the VPC and add the network interface policy."
  }
}

run "subnets_without_security_groups_are_refused" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.security_group_ids]
}

run "the_role_gets_only_logs_kms_and_the_given_statements" {
  command = apply

  variables {
    policy_statements = [{
      sid       = "SendToQueue"
      actions   = ["sqs:SendMessage"]
      resources = ["arn:aws:sqs:eu-west-1:123456789012:ordering-integration-jobs"]
    }]
  }

  assert {
    condition     = toset([for statement in data.aws_iam_policy_document.this.statement : statement.sid]) == toset(["WriteOwnLogs", "DecryptEnvironment", "SendToQueue"])
    error_message = "The role holds log writing, kms:Decrypt on the environment key and the statements passed in, nothing else."
  }

  assert {
    condition     = alltrue([for statement in data.aws_iam_policy_document.this.statement : !contains(statement.resources, "*")])
    error_message = "No statement may name every resource."
  }
}

run "environment_variables_are_passed_through" {
  command = apply

  variables {
    environment_variables = { QUEUE_URL = "https://sqs.eu-west-1.amazonaws.com/123456789012/ordering-integration-jobs" }
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables["QUEUE_URL"] == "https://sqs.eu-west-1.amazonaws.com/123456789012/ordering-integration-jobs"
    error_message = "The map must reach the function."
  }
}

run "function_name_is_exposed_for_the_deploy_workflow" {
  command = apply

  assert {
    condition     = output.function_name == "ordering-integration-intake"
    error_message = "function_name is what the deploy workflow targets."
  }
}

run "architectures_are_validated" {
  command = plan

  variables {
    architectures = ["mips"]
  }

  expect_failures = [var.architectures]
}
