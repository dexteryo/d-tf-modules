# ecs-cluster

ECS cluster with Container Insights, the `FARGATE` and `FARGATE_SPOT` capacity providers and optional ECS Exec logging.

## Usage

```hcl
module "cluster" {
  source = "git::https://github.com/dexteryo/dex-tf-modules.git//modules/ecs-cluster?ref=v0.1.0"

  name        = "ai-integration"
  environment = "integration"
}
```

## Notes

- Both capacity providers are always registered. `default_capacity_provider_strategy` decides which one services use when they set no strategy; the default is `FARGATE` only.
- With `enable_execute_command_logging = true` the module creates `/ecs/<name>/execute-command` and sends ECS Exec session logs there. Pass `execute_command_kms_key_arn` to encrypt the session and `execute_command_log_kms_key_arn` to encrypt the log group. Whoever starts sessions still needs `ecs:ExecuteCommand`; tasks need `enable_execute_command` on the service module.

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
| [aws_cloudwatch_log_group.execute_command](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| name | Cluster name | `string` | n/a | yes |
| default\_capacity\_provider\_strategy | Default capacity provider strategy for services that do not set their own | ```list(object({ capacity_provider = string weight = number base = optional(number, 0) }))``` | ```[ { "base": 0, "capacity_provider": "FARGATE", "weight": 1 } ]``` | no |
| enable\_container\_insights | Enable CloudWatch Container Insights | `bool` | `true` | no |
| enable\_execute\_command\_logging | Send ECS Exec session logs to a dedicated CloudWatch log group | `bool` | `false` | no |
| execute\_command\_kms\_key\_arn | KMS key ARN used to encrypt ECS Exec sessions | `string` | `null` | no |
| execute\_command\_log\_kms\_key\_arn | KMS key ARN used to encrypt the ECS Exec log group | `string` | `null` | no |
| execute\_command\_log\_retention\_days | Retention of the ECS Exec log group in days | `number` | `30` | no |
| tags | Tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | ARN of the ECS cluster |
| cluster\_name | Name of the ECS cluster |
| execute\_command\_log\_group\_name | Log group receiving ECS Exec sessions, when enabled |
<!-- END_TF_DOCS -->
