mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-west-1:123456789012:ordering-integration-jobs"
      id  = "https://sqs.eu-west-1.amazonaws.com/123456789012/ordering-integration-jobs"
      url = "https://sqs.eu-west-1.amazonaws.com/123456789012/ordering-integration-jobs"
    }
  }
}

variables {
  name        = "ordering"
  environment = "integration"
  name_suffix = "jobs"
  tags        = { Environment = "integration" }
  kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

run "both_queues_are_encrypted_and_named_from_the_inputs" {
  command = apply

  assert {
    condition     = aws_sqs_queue.this.kms_master_key_id == var.kms_key_arn && aws_sqs_queue.dlq.kms_master_key_id == var.kms_key_arn
    error_message = "Both queues must use the given key."
  }

  assert {
    condition     = aws_sqs_queue.this.name == "ordering-integration-jobs" && aws_sqs_queue.dlq.name == "ordering-integration-jobs-dlq"
    error_message = "The queue is named <name>-<environment>-<name_suffix> and the dead-letter queue adds -dlq."
  }

  assert {
    condition     = aws_sqs_queue.this.tags["Environment"] == "integration" && aws_sqs_queue.dlq.tags["Environment"] == "integration"
    error_message = "Tags must be applied to both queues."
  }
}

run "the_name_suffix_is_optional" {
  command = plan

  variables {
    name_suffix = null
  }

  assert {
    condition     = aws_sqs_queue.this.name == "ordering-integration"
    error_message = "Without a suffix the queue is named <name>-<environment>."
  }
}

run "the_queue_moves_a_message_to_the_dlq_after_max_receive_count" {
  command = apply

  variables {
    max_receive_count = 3
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 3
    error_message = "maxReceiveCount must follow the input."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_allow_policy.dlq.redrive_allow_policy).redrivePermission == "byQueue"
    error_message = "Only the queue may redrive into the dead-letter queue."
  }
}

run "max_receive_count_is_validated" {
  command = plan

  variables {
    max_receive_count = 0
  }

  expect_failures = [var.max_receive_count]
}

run "both_queues_refuse_plain_http" {
  command = apply

  assert {
    condition = alltrue([
      for key in ["queue", "dlq"] :
      one([for statement in data.aws_iam_policy_document.tls_only[key].statement : statement.effect]) == "Deny"
    ])
    error_message = "Each queue policy has one statement and it only denies. It never adds a public Allow."
  }

  assert {
    condition = alltrue([
      for key in ["queue", "dlq"] :
      one([for statement in data.aws_iam_policy_document.tls_only[key].statement : one([for c in statement.condition : c.variable])]) == "aws:SecureTransport"
    ])
    error_message = "The deny applies to requests without TLS."
  }

  assert {
    condition     = length(aws_sqs_queue_policy.tls_only) == 2
    error_message = "Both queues get the policy."
  }
}

run "the_alarm_watches_the_dlq_and_notifies_the_given_targets" {
  command = apply

  variables {
    alarm_actions = ["arn:aws:sns:eu-west-1:123456789012:ordering-integration-alarms"]
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dlq_not_empty.dimensions["QueueName"] == "ordering-integration-jobs-dlq" && aws_cloudwatch_metric_alarm.dlq_not_empty.threshold == 1
    error_message = "The alarm fires at one visible message in the dead-letter queue."
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_actions, "arn:aws:sns:eu-west-1:123456789012:ordering-integration-alarms")
    error_message = "alarm_actions must reach the alarm."
  }
}
