mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-1:123456789012:ordering-integration-alarms"
    }
  }
}

variables {
  name        = "ordering"
  environment = "integration"
  tags        = { Environment = "integration" }
  kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

run "topic_is_encrypted_and_named_from_the_inputs" {
  command = apply

  assert {
    condition     = aws_sns_topic.this.kms_master_key_id == var.kms_key_arn
    error_message = "The topic must be encrypted with the given key."
  }

  assert {
    condition     = aws_sns_topic.this.name == "ordering-integration-alarms" && output.topic_name == "ordering-integration-alarms"
    error_message = "The topic is named <name>-<environment>-<name_suffix>."
  }

  assert {
    condition     = aws_sns_topic.this.tags["Environment"] == "integration"
    error_message = "Tags must be applied."
  }
}

run "only_cloudwatch_of_this_account_may_publish" {
  command = apply

  assert {
    condition     = jsondecode(aws_sns_topic_policy.cloudwatch_alarms[0].policy).Statement[0].Principal.Service == "cloudwatch.amazonaws.com" && jsondecode(aws_sns_topic_policy.cloudwatch_alarms[0].policy).Statement[0].Action == "sns:Publish"
    error_message = "CloudWatch may publish and nothing else."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.cloudwatch_alarms[0].policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "The publish permission must be pinned to this account."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.cloudwatch_alarms[0].policy).Statement[0].Resource == "arn:aws:sns:eu-west-1:123456789012:ordering-integration-alarms"
    error_message = "The permission must name the topic."
  }
}

run "the_alarm_policy_can_be_left_out" {
  command = apply

  variables {
    allow_cloudwatch_alarms = false
  }

  assert {
    condition     = length(aws_sns_topic_policy.cloudwatch_alarms) == 0
    error_message = "allow_cloudwatch_alarms = false must remove the topic policy."
  }
}

run "no_subscriptions_by_default" {
  command = apply

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0 && length(aws_sns_topic_subscription.https) == 0
    error_message = "Subscriptions are opt-in."
  }
}

run "subscriptions_are_created_for_every_endpoint" {
  command = apply

  variables {
    email_addresses = ["alerts@example.com", "oncall@example.com"]
    https_endpoints = ["https://hooks.example.com/alarms"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 2 && aws_sns_topic_subscription.email["alerts@example.com"].protocol == "email"
    error_message = "Every address gets an email subscription."
  }

  assert {
    condition     = aws_sns_topic_subscription.https["https://hooks.example.com/alarms"].protocol == "https"
    error_message = "Every endpoint gets an https subscription."
  }
}

run "plain_http_endpoints_are_refused" {
  command = plan

  variables {
    https_endpoints = ["http://hooks.example.com/alarms"]
  }

  expect_failures = [var.https_endpoints]
}
