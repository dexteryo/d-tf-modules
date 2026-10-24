# ecs-cluster

One ECS cluster for Fargate: Container Insights, the `FARGATE` and `FARGATE_SPOT` capacity providers and optional encrypted ECS Exec logging.

## Owns

- `aws_ecs_cluster` named `<name>-<environment>`, its capacity provider association and default strategy.
- The ECS Exec session log group, only when `enable_execute_command_logging` is true.

## Does not own

- Services (`ecs-service`), alarms (`ecs-service-alarms`) or the keys used for Exec encryption (`kms`).
- Any EC2 capacity. The cluster is Fargate only.

## Usage

```hcl
module "cluster" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/ecs-cluster?ref=v0.3.0"

  name        = "ordering"
  environment = "integration"
  tags        = module.tags.all_tags
}
```

Feed `cluster_arn` to `ecs-service` and `cluster_name` to `ecs-service-alarms` and to the deploy workflow.

## Defaults worth knowing

- Container Insights is on; the alarms in `ecs-service-alarms` read its metrics.
- Services without their own strategy run on `FARGATE`.
- ECS Exec logging is off. When on, give `execute_command_log_kms_key_arn` so the log group is encrypted.

## Left out of the reference shape

The reference cluster modules also manage EC2 container instances, auto scaling groups, launch templates, agent bootstrap scripts, a log forwarder sidecar, instance IAM and an internal load balancer. None of that exists for a Fargate-only cluster.

## Tests

`terraform test` with `mock_provider "aws"` covers Container Insights, both capacity providers, naming and tags, the default strategy, encrypted Exec logging and the capacity provider validation.

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
| aws | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.execute_command](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| name | Workload name. The cluster is named <name>-<environment> | `string` | n/a | yes |
| default\_capacity\_provider\_strategy | Default capacity provider strategy for services that do not set their own | ```list(object({ capacity_provider = string weight = number base = optional(number, 0) }))``` | ```[ { "base": 0, "capacity_provider": "FARGATE", "weight": 1 } ]``` | no |
| enable\_container\_insights | Enable CloudWatch Container Insights | `bool` | `true` | no |
| enable\_execute\_command\_logging | Send ECS Exec session logs to a dedicated CloudWatch log group | `bool` | `false` | no |
| execute\_command\_kms\_key\_arn | KMS key ARN used to encrypt ECS Exec sessions | `string` | `null` | no |
| execute\_command\_log\_kms\_key\_arn | KMS key ARN used to encrypt the ECS Exec log group | `string` | `null` | no |
| execute\_command\_log\_retention\_days | Retention of the ECS Exec log group in days | `number` | `30` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | ARN of the ECS cluster |
| cluster\_id | ID of the ECS cluster |
| cluster\_name | Name of the ECS cluster |
| execute\_command\_log\_group\_name | Log group receiving ECS Exec sessions, when enabled |
<!-- END_TF_DOCS -->