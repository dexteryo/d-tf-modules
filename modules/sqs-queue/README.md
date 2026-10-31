# sqs-queue

One encrypted SQS queue with a dead-letter queue, a policy that refuses plain HTTP, and an alarm that fires when a message lands in the dead-letter queue.

## Owns

- `aws_sqs_queue` named `<name>-<environment>[-<name_suffix>]`, encrypted with the key you give it, and its dead-letter queue `<...>-dlq`.
- Redrive after `max_receive_count` receives (5 by default), and a redrive allow policy so only this queue can feed the dead-letter queue.
- A queue policy on each queue that denies every request without TLS. It only denies; it never grants anyone access.
- A CloudWatch alarm that fires at one visible message in the dead-letter queue and notifies `alarm_actions`.

## Does not own

- The KMS key (`kms`). Producers need `kms:GenerateDataKey` and `kms:Decrypt` on it, consumers `kms:Decrypt`.
- Who may send or receive. Grant `sqs:SendMessage` or the receive actions in the producer's or consumer's role, on `queue_arn` only.
- The alarm topic (`sns-topic`). Pass its `topic_arn` as `alarm_actions`.
- The consumer. Event source mappings belong to the function that reads the queue.

## Usage

```hcl
module "jobs" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/sqs-queue?ref=v0.6.0"

  name          = "ordering"
  environment   = "integration"
  name_suffix   = "jobs"
  tags          = module.tags.all_tags
  kms_key_arn   = module.jobs_key.kms_key_arn
  alarm_actions = [module.alarm_topic.topic_arn]
}
```

Set `visibility_timeout_seconds` above the consumer's timeout, or a slow message is received twice.

## Tests

`terraform test` with `mock_provider "aws"` covers encryption, naming, the optional suffix, redrive, the `max_receive_count` validation, the TLS-only policies and the alarm.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 6.71.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_metric_alarm.dlq_not_empty](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.tls_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_sqs_queue_redrive_allow_policy.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_allow_policy) | resource |
| [aws_iam_policy_document.tls_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| kms\_key\_arn | Customer-managed key that encrypts both queues. Producers and consumers need kms:GenerateDataKey and kms:Decrypt on it | `string` | n/a | yes |
| name | Workload name. The queue is named <name>-<environment>[-<name\_suffix>] and its dead-letter queue adds -dlq | `string` | n/a | yes |
| alarm\_actions | ARNs notified when the dead-letter queue holds a message, usually the topic\_arn of the sns-topic module. Empty keeps the alarm without a notification | `list(string)` | `[]` | no |
| max\_receive\_count | Receives of one message before SQS moves it to the dead-letter queue | `number` | `5` | no |
| message\_retention\_seconds | How long the queue and the dead-letter queue keep a message. The default is 14 days, the SQS maximum | `number` | `1209600` | no |
| name\_suffix | Optional last part of the name, for example jobs | `string` | `null` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| visibility\_timeout\_seconds | How long a received message stays hidden. Set it above the consumer's timeout | `number` | `60` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dlq\_alarm\_arn | ARN of the alarm that fires while the dead-letter queue holds a message |
| dlq\_arn | ARN of the dead-letter queue |
| dlq\_name | Name of the dead-letter queue |
| dlq\_url | URL of the dead-letter queue |
| queue\_arn | ARN of the queue; grant producers sqs:SendMessage and consumers the receive actions on it |
| queue\_name | Name of the queue |
| queue\_url | URL of the queue |
<!-- END_TF_DOCS -->
