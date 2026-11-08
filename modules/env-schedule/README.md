# env-schedule

Stops a non-production environment outside working hours and starts it again: ECS services scale to zero and RDS instances stop on one cron, then databases and services start on two later crons. With no start cron the environment stays off until an operator starts it.

## Owns

- An EventBridge Scheduler schedule group named `<name>-<environment>`.
- Per DB instance, a `stop-db-<key>` and a `start-db-<key>` schedule calling `rds:StopDBInstance` and `rds:StartDBInstance`.
- Per ECS service, a `stop-svc-<key>` schedule that sets the desired count to 0 and a `start-svc-<key>` schedule that sets it back to `desired_count`.
- The scheduler role `<name>-<environment>-scheduler`, assumable only by `scheduler.amazonaws.com` from this account, allowed to start and stop the named DB instances and update the named services, nothing else.
- Optionally, the operator role `<name>-<environment>-operator`, assumable through GitHub OIDC by one repository environment, with the same target permissions plus read access to this group's schedules and the targets' status.

## Does not own

- The services and databases. Pass their names; the module builds the ARNs in the current account and region.
- The GitHub OIDC provider. Pass its ARN in `operator.oidc_provider_arn`.
- The operator workflow. `d-github-actions` `env-power.yml` assumes the operator role, reads the schedules in the group and replays their targets now.

## Usage

```hcl
module "schedule" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/env-schedule?ref=v0.7.0"

  name          = "ordering"
  environment   = "integration"
  tags          = module.tags.all_tags
  timezone      = "Europe/Dublin"
  stop_schedule = "cron(0 20 ? * MON-FRI *)"

  start_schedule = {
    databases = "cron(40 7 ? * MON-FRI *)"
    services  = "cron(55 7 ? * MON-FRI *)"
  }

  ecs_services = {
    api = { cluster_name = module.cluster.cluster_name, service_name = module.api.service_name }
  }

  db_instances = {
    main = module.database.db_identifier
  }
}
```

## Defaults worth knowing

- **Start order.** A service whose tasks connect to the database fails its health checks while the database is starting, and ECS keeps replacing the tasks. Start databases about 15 minutes before services.
- **Stopped databases restart after seven days.** RDS starts a stopped instance again after seven days. A stop cron that runs at least weekly stops it again.
- **No start cron.** With `start_schedule = null` the start schedules still exist, disabled and set to a date that never comes, so the operator workflow can read their targets.
- **Terraform and desired count.** A service created with `manage_task_definition_externally = true` in `ecs-service` already ignores `desired_count`. A Terraform-managed one needs `ignore_desired_count = true`, or an apply while the environment is off starts it again.
- **Applies while stopped.** Terraform cannot modify a stopped DB instance. Start the environment before an apply that changes the database, and before running migrations.
- **Retries.** Each target is retried up to three times within an hour. Stopping an instance that is already stopped fails without harm.
- **Schedule names** are `<group>-<stop|start>-<db|svc>-<key>`, which the operator workflow relies on. Keys are at most 16 characters so names stay under the 64-character limit.

## Left out on purpose

- Stopping on idle traffic. A fixed cron is predictable and has no alarm to tune; the operator workflow covers ad hoc use.
- Aurora clusters, RDS Proxy and load balancers. Proxies and load balancers cannot be stopped, only deleted.
- A customer managed key for schedules. Schedule inputs hold resource names only.

## Tests

`terraform test` with `mock_provider "aws"` covers naming, the stop targets and inputs, disabled start schedules, start order, the scheduler trust and its exact permissions, the operator role and its subject claims, and every validation.

## Example

[`examples/basic`](examples/basic) schedules one service and one database on weekday working hours and adds an operator role.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_scheduler_schedule.start_database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.start_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.stop_database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule.stop_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule_group) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Environment name, appended to the base name | `string` | n/a | yes |
| name | Base name for the schedule group, schedules and roles | `string` | n/a | yes |
| stop\_schedule | EventBridge Scheduler cron expression for stopping, for example cron(0 23 ? * MON-FRI *). Services scale to zero and databases stop at the same time | `string` | n/a | yes |
| db\_instances | RDS DB instance identifiers to stop and start, keyed by a short stable name. Instances in a cluster and Multi-AZ SQL Server instances cannot be stopped | `map(string)` | `{}` | no |
| ecs\_services | ECS services to scale to zero and back, keyed by a short stable name. desired\_count is the count the start restores. A Terraform-managed service needs ignore\_desired\_count = true in ecs-service | ```map(object({ cluster_name = string service_name = string desired_count = optional(number, 1) }))``` | `{}` | no |
| operator | Create a role that one GitHub repository environment can assume through OIDC to read these schedules and start or stop the same targets on demand. Null creates no role | ```object({ github_repository = string github_environment = string oidc_provider_arn = string github_immutable_ids = optional(object({ owner_id = number repository_id = number })) })``` | `null` | no |
| start\_schedule | Cron expressions for starting: databases first, services later, because a service cannot boot while its database is still starting (allow about 15 minutes). Null keeps the start schedules disabled, so the environment only starts when an operator starts it | ```object({ databases = string services = string })``` | `null` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| timezone | IANA time zone the cron expressions are read in, for example Asia/Ho\_Chi\_Minh. Daylight saving changes are followed | `string` | `"UTC"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| operator\_role\_arn | ARN of the GitHub OIDC operator role, or null when operator is not set |
| schedule\_group\_name | Name of the schedule group. The operator workflow reads the targets of its schedules |
| scheduler\_role\_arn | ARN of the role EventBridge Scheduler uses to reach the targets |
<!-- END_TF_DOCS -->
