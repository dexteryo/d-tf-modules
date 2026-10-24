# rds-postgres

One RDS for PostgreSQL instance that is encrypted, private and TLS-only, with generated credentials per application role and an optional RDS Proxy in front.

## Owns

- The instance, its subnet group and a parameter group that forces TLS 1.2 or later.
- Storage, backup, Performance Insights and administrator-secret encryption with the `data_kms_key_arn` key.
- The administrator password, which RDS creates and keeps in Secrets Manager.
- The PostgreSQL and upgrade log groups (encrypted with `logs_kms_key_arn`), the enhanced monitoring role and a free-storage alarm.
- One generated password and one Secrets Manager secret per entry in `database_roles`.
- With `proxy` set: the RDS Proxy, its role and the target group, signing in as the roles you list.

## Does not own

- Security groups. Build the instance's and the proxy's with `modules/security-group`, admitting only the callers, and pass the IDs. The callers' own egress rules to the database are also the caller's.
- The network. Pass isolated subnets from `modules/vpc`.
- The keys. Create them with `modules/kms`.
- The databases and roles inside PostgreSQL. Terraform cannot reach an isolated instance, so a bootstrap step in the caller (for example a one-off ECS task) creates them, reads the administrator secret from `master_user_secret_arn` and each role's password from `role_secret_arns`, and makes the roles match.
- Secret rotation.

## Usage

```hcl
module "database" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/rds-postgres?ref=v0.3.0"

  name                  = "ordering"
  environment           = "production"
  subnet_ids            = module.vpc.isolated_subnet_ids
  security_group_ids    = [module.db_security_group.security_group_id]
  data_kms_key_arn      = module.data_key.kms_key_arn
  logs_kms_key_arn      = module.logs_key.kms_key_arn
  multi_az              = true
  backup_retention_days = 35
  alarm_topic_arns      = [module.alarms.topic_arn]
  tags                  = module.tags.all_tags

  database_roles = {
    ordering_api = { database = "ordering" }
  }

  proxy = {
    role_names         = ["ordering_api"]
    security_group_ids = [module.proxy_security_group.security_group_id]
  }
}
```

The instance is named `ordering-production-postgres`, and the role secret `ordering-production/db/ordering_api`.

## Defaults worth knowing

- Deletion protection and a final snapshot are on. Turn them off for a nonprod environment that you rebuild.
- Backups are kept for 7 days, which is also how far back a point-in-time restore reaches. The maximum is 35.
- The instance is single-AZ until `multi_az = true`.
- Changing `master_username` replaces the instance.
- The proxy requires TLS and signs in with SCRAM. A role used by something that must connect straight to the instance (for example an identity provider) can be left out of `proxy.role_names`.
- Query logging is not turned on, because statement text can hold personal data.

## Tests

`terraform test` with `mock_provider "aws"` covers naming and tags, encryption, privacy and TLS, backup and deletion defaults and overrides, log exports, the storage alarm, role secrets, the proxy and its precondition, and input validation.

## Example

`examples/basic` in this directory composes the module with `tags`, `kms`, `vpc` and `security-group`, and validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 6.0 |
| random | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 6.70.0 |
| random | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.postgresql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.free_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_proxy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy) | resource |
| [aws_db_proxy_default_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy_default_target_group) | resource |
| [aws_db_proxy_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy_target) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [random_password.role](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| data\_kms\_key\_arn | Key that encrypts storage, backups, Performance Insights and the secrets | `string` | n/a | yes |
| logs\_kms\_key\_arn | Key that encrypts the PostgreSQL log groups | `string` | n/a | yes |
| name | Workload name. The instance is named <name>-<environment>[-<name\_suffix>]-postgres | `string` | n/a | yes |
| security\_group\_ids | Security groups of the instance. They decide who can connect; build them with the security-group module | `list(string)` | n/a | yes |
| subnet\_ids | Isolated subnets, in at least two zones, for the instance and the proxy | `list(string)` | n/a | yes |
| alarm\_topic\_arns | SNS topics notified when the alarm fires and when it clears | `list(string)` | `[]` | no |
| allocated\_storage\_gb | Initial storage in GiB | `number` | `20` | no |
| backup\_retention\_days | Days of automated backups, which is also the window for point-in-time restore (1 to 35) | `number` | `7` | no |
| backup\_window | Daily backup window in UTC | `string` | `"05:00-06:00"` | no |
| database\_roles | One entry per application role, keyed by role name: the database it belongs to. Each gets a generated password in its own Secrets Manager secret. This module does not create the roles or databases inside PostgreSQL; a bootstrap step in the caller does | ```map(object({ database = string }))``` | `{}` | no |
| deletion\_protection | Block deletion of the instance | `bool` | `true` | no |
| engine\_version | PostgreSQL major version; AWS applies minor versions | `string` | `"17"` | no |
| environment | Deployment environment, for example integration or production | `string` | `""` | no |
| free\_storage\_alarm\_bytes | Free storage below which the alarm fires, in bytes | `number` | `5368709120` | no |
| instance\_class | Instance class | `string` | `"db.t4g.medium"` | no |
| log\_retention\_days | Days to keep the PostgreSQL and upgrade logs | `number` | `365` | no |
| maintenance\_window | Weekly maintenance window in UTC | `string` | `"sun:06:30-sun:07:30"` | no |
| master\_username | Administrator user name. RDS creates and manages its password in Secrets Manager. Changing it replaces the instance | `string` | `"dbadmin"` | no |
| max\_allocated\_storage\_gb | Ceiling for storage autoscaling in GiB | `number` | `200` | no |
| multi\_az | Multi-AZ instance | `bool` | `false` | no |
| name\_suffix | Optional part of the name, for example reporting when one workload has several databases | `string` | `""` | no |
| proxy | RDS Proxy in front of the instance. role\_names are the database\_roles the proxy may sign in as, and security\_group\_ids are the proxy's own groups. Null for no proxy | ```object({ role_names = set(string) security_group_ids = list(string) idle_client_timeout = optional(number, 1800) })``` | `null` | no |
| skip\_final\_snapshot | Skip the snapshot taken when the instance is destroyed | `bool` | `false` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| db\_arn | Instance ARN |
| db\_endpoint | Instance address, for clients that connect without the proxy |
| db\_identifier | Instance identifier, <name>-<environment>-postgres; the point-in-time restore runbook names it |
| db\_port | PostgreSQL port |
| master\_user\_secret\_arn | Secret that RDS manages for the administrator account |
| proxy\_endpoint | RDS Proxy endpoint, or null when there is no proxy |
| role\_secret\_arns | Secrets Manager secret of each database role, keyed by role name |
<!-- END_TF_DOCS -->
