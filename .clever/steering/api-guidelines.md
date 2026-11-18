# API guidelines

> Generated 2026-10-31 (INIT) from `v0.5.1`. A module's API is its variables and outputs; there are no HTTP APIs in this repository.

## Inputs

Shape, as consistently observed:

- Required inputs have no `default`. Everything else defaults to the safe choice (closed, encrypted, protected) and the README's "Defaults worth knowing" explains it.
- Common inputs appear with the same name, type and description in every module: `name` (string), `environment` (string), `name_suffix` (string, `""`), `tags` (`map(string)`, `{}`).
- Things the module wires together are passed by ID or ARN, never looked up by name: `vpc_id`, `subnet_ids`, `security_group_ids`, `cluster_arn`, `listener_arn`, `kms_key_arn`, `hosted_zone_id`, `oidc_provider_arn`, `certificate_arn`, `web_acl_arn`.
- KMS inputs are named for what they encrypt when a module takes more than one: `data_kms_key_arn` / `logs_kms_key_arn` (`rds-postgres`), `log_kms_key_arn` / `kms_key_arns` (`ecs-service`), `logs_kms_key_arn` (`vpc`).
- A feature is switched on by giving its object (`load_balancer`, `autoscaling`, `proxy`, `access_logs`, `github_immutable_ids`), or by a boolean when there is nothing to configure (`cloudfront_only`, `enable_execute_command`, `create_kms_key`).
- Collections that become `for_each` keys are maps with stable, caller-chosen keys (`ingress_rules`, `listeners`, `header_forward_rules`, `backends`, `database_roles`). Values that must not be keys go in a parallel map (`header_values`, marked `sensitive`).
- Units go in the name: `_days`, `_seconds`, `_gb`, `_bytes`, `_per_5_minutes`.
- `nullable = false` is used where a null would silently fall back to a weaker setting (`modules/s3-bucket/variables.tf:4,39`).

Validation rules are listed in `coding-standards.md`. Invalid input must fail at plan, with a message that names the variable.

## Outputs

- Every output has a description, often telling the caller where to pass it ("pass it as alarm_actions to the ecs-service-alarms module", `modules/sns-topic/outputs.tf`; "pass it as role-to-assume to the workflows of d-github-actions", `modules/ci-oidc-role/outputs.tf:2`).
- Names carry the resource type: `kms_key_arn`, `security_group_id`, `alb_arn`, `alb_arn_suffix`, `bucket_arn`, `cluster_arn`, `role_arn`, `topic_arn`, `web_acl_arn`, `distribution_arn`, `certificate_arn`, `db_endpoint`, `proxy_endpoint`.
- `_arn_suffix` outputs exist for CloudWatch dimensions (`alb_arn_suffix`, `target_group_arn_suffix`).
- Optional resources produce `null` through `one(resource[*].attr)` rather than an error (`target_group_arn`, `proxy_endpoint`, `execute_command_log_group_name`).
- Keyed inputs produce keyed outputs with the same keys (`listener_arns`, `ingress_rules`, `role_secret_arns`, `alarm_arns`).
- Some modules expose "as created" summaries for review and for tests in the caller (`alb` `load_balancer` and `listeners`, `ecs-service-alarms` `alarms`, `security-group` `ingress_rules`/`egress_rules`).
- Outputs that carry secrets are `sensitive` (`alb` `header_forward_rules`). Secret values themselves are not output; `rds-postgres` outputs secret ARNs only.

## Versioning

Semantic Versioning with Keep a Changelog (`CHANGELOG.md` header). Tags are `vX.Y.Z`. All modules share one version: a release tags the whole repository, and a caller pins every module to the same ref (`README.md:83`; `finn-app-brazil` pins all 26 of its module calls to one hash).

The project is pre-1.0. What the CHANGELOG shows about how bumps are chosen:

| Release | Bump | Content |
| --- | --- | --- |
| 0.2.0 | minor | Breaking: `ecs-service` lost `vpc_id`, `load_balancer.alb_security_group_id`, output `security_group_id` and its security group resources; `ecs-cluster` naming changed. Migration section included |
| 0.2.1 | patch | Repository rename, no functional change |
| 0.3.0 | minor | Breaking: AWS provider `~> 5.0` → `~> 6.0`, marked **Breaking:** in `Changed`. Migration section included. Also new modules and a stricter `s3-bucket` input (null key refused) |
| 0.3.1 | patch | New optional inputs on `ecs-service` (`command`, `entry_point`, health check timing) |
| 0.4.0 | minor | New module `acm-certificate` |
| 0.5.0 | minor | New optional inputs on `ci-oidc-role` |
| 0.5.1 | patch | New optional input `github_immutable_ids` on `ci-oidc-role` |

So, as practised: breaking changes and new modules bump the minor version while below 1.0; new optional inputs have been released as both minor (0.5.0) and patch (0.3.1, 0.5.1). There is no written rule that resolves that difference.

A breaking release states it in the CHANGELOG with "**Breaking:**" or under `Removed`, and adds a `### Migration from vA.B.x` section with numbered steps: what to change in the caller, resource address moves (`moved` blocks or `terraform state mv`), and the new ref to pin (`CHANGELOG.md` `[0.2.0]`, `[0.3.0]`). Commits that break the interface use `!` in the Conventional Commit type (`feat!:`).

## Compatibility rules visible in the code

- New inputs are added as optional with a default that keeps the old behaviour (every addition in 0.3.1, 0.5.0, 0.5.1).
- Statements, resources or blocks driven by a new list input are omitted while the list is empty, so existing plans do not change (`ci-oidc-role` static-site statements, `CHANGELOG.md` `[0.5.0]`).
- Switching an input that changes resource identity is called out in the README (for example `manage_task_definition_externally` recreates the service).
