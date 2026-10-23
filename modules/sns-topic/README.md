# sns-topic

One encrypted SNS topic for alarms, a policy that lets CloudWatch publish, and email or HTTPS subscriptions.

## Owns

- `aws_sns_topic` named `<name>-<environment>-<name_suffix>` (suffix `alarms` by default), encrypted with the key you give it.
- A topic policy that lets `cloudwatch.amazonaws.com` publish, pinned to this account with `aws:SourceAccount`.
- Email and HTTPS subscriptions.

## Does not own

- The KMS key (`kms`). Its policy must allow `cloudwatch.amazonaws.com` to use it (`kms:Decrypt` and `kms:GenerateDataKey*`); the AWS-managed `aws/sns` key cannot be used by alarms.
- The alarms themselves (`ecs-service-alarms`).
- Subscription confirmation. Terraform cannot confirm an email or HTTPS subscription; each owner confirms it by hand.

## Usage

```hcl
module "alarm_topic" {
  source = "git::ssh://git@github.com/dexteryo/dex-tf-modules.git//modules/sns-topic?ref=v0.2.0"

  name            = "ordering"
  environment     = "integration"
  tags            = module.tags.all_tags
  kms_key_arn     = module.alarm_key.kms_key_arn
  email_addresses = ["alerts@example.com"]
}
```

## Left out of the reference shape

The reference module creates email subscriptions through a CloudFormation stack, supports SMS numbers and keeps a second topic for stack events, with a default key owned by another team. This module uses the native subscription resource for email and HTTPS, has no SMS or CloudFormation, and has no default key: `kms_key_arn` is required.

## Tests

`terraform test` with `mock_provider "aws"` covers encryption, naming, the account-pinned CloudWatch policy, leaving the policy out, subscriptions and the HTTPS validation.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 5.100.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_sns_topic.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.cloudwatch_alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| kms\_key\_arn | Customer-managed key that encrypts the topic. Its key policy must let cloudwatch.amazonaws.com use it (kms:Decrypt and kms:GenerateDataKey*) or alarms cannot publish; the aws/sns key cannot be used for that | `string` | n/a | yes |
| name | Workload name. The topic is named <name>-<environment>[-<name\_suffix>] | `string` | n/a | yes |
| allow\_cloudwatch\_alarms | Let CloudWatch alarms of this account publish to the topic | `bool` | `true` | no |
| email\_addresses | Addresses subscribed to the topic. Each owner must confirm the subscription by hand, Terraform cannot | `list(string)` | `[]` | no |
| https\_endpoints | HTTPS endpoints subscribed to the topic, for example a chat webhook. The endpoint must confirm the subscription | `list(string)` | `[]` | no |
| name\_suffix | Optional last part of the name, for example alarms | `string` | `"alarms"` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| topic\_arn | ARN of the topic; pass it as alarm\_actions to the ecs-service-alarms module |
| topic\_name | Name of the topic |
<!-- END_TF_DOCS -->