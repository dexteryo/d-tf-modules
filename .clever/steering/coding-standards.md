# Coding standards

> Generated 2026-10-31 (INIT). Only patterns seen consistently across the 16 modules are listed; exceptions are named.

## Files

One module per folder with `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`, `examples/basic/main.tf` and `tests/<name>.tftest.hcl` (all 16 modules). `versions.tf` holds only the `terraform {}` block. Split `main.tf` by concern once it grows (`iam.tf`, `locals.tf`, `roles.tf`, `proxy.tf`, `endpoints.tf`, `flow_logs.tf`, `backends.tf`, `access_logs.tf`). Non-HCL assets go in a subfolder and are read with `file("${path.module}/...")` (`modules/cloudfront-spa/main.tf:23`).

There are no comments in any `.tf` file in the repository (`git grep -nE '^\s*(#|//)' HEAD -- '*.tf'` returns nothing at `v0.5.1`). Explanations live in variable and output descriptions and in the README.

## Naming

Resource-naming modules take `name`, `environment` and, in most modules, `name_suffix`, and build:

```hcl
full_name = join("-", compact([var.name, var.environment, var.name_suffix]))
```

Used in `kms`, `security-group`, `s3-bucket`, `vpc`, `rds-postgres`, `waf-web-acl`, `cloudfront-spa`, `acm-certificate`, `sns-topic`, `ci-oidc-role`. `compact` lets `environment` and `name_suffix` be empty for shared resources. Modules whose names must always carry an environment use plain interpolation `"${var.name}-${var.environment}"` and make `environment` required: `alb`, `ecs-cluster`, `ecs-service`, `ecs-service-alarms`. `ecr` takes only `name` and an optional `namespace` (repositories are shared by every environment, `README.md` "Naming is built from inputs").

Suffixes appended inside a module are fixed words: `-execution`, `-task` (`ecs-service/iam.tf`), `-postgres`, `-monitoring`, `-proxy` (`rds-postgres`), `-vpc-flow`, `-vpc-endpoints` (`vpc`), `-spa-rewrite` (`cloudfront-spa`), `-cpu-high`, `-memory-high` and others (`ecs-service-alarms`).

Where AWS needs a unique name and replacement must not collide, modules use `name_prefix` with `create_before_destroy`: `aws_security_group` (`security-group/main.tf:7,12-14`), `aws_db_parameter_group` (`rds-postgres/main.tf:14,29-31`), `aws_lb_target_group` (`name_prefix = substr(var.name, 0, 6)`, `ecs-service/main.tf:36,52-54`). `aws_acm_certificate` also uses `create_before_destroy`.

HCL identifiers: the single main resource of a module is `this` (`aws_kms_key.this`, `aws_lb.this`, `aws_ecs_cluster.this`). Additional resources are named for their role (`aws_iam_role.execution`, `aws_iam_role.task`, `aws_lb_listener_rule.header_forward`, `aws_cloudwatch_log_group.flow`). Map-keyed inputs use stable string keys "that stay the same between runs" (`security-group/variables.tf:35`, `alb/variables.tf:105`).

## Tags

Every module that creates resources takes `variable "tags" { type = map(string), default = {} }` with the description "Tags for every resource, usually the all_tags output of the tags module". Taggable resources get `merge(var.tags, { Name = <full name> })`; secondary resources (rules, policies, log groups in some modules) get `var.tags` unchanged. Modules do not invent other tag keys, with one exception: `vpc` subnets add `Tier = public|private|isolated` (`modules/vpc/main.tf:39-66`). `ecs-service` sets `propagate_tags = "SERVICE"`.

The `tags` module itself enforces the tag vocabulary: mandatory `Environment`, `Service`, `Repository` plus `ManagedBy = "terraform"`; optional `Owner`, `CostCentre`, `DataClassification`, `Component`; free-form custom tags must not reuse those keys; environment and service are lower-cased (`modules/tags/main.tf`, `outputs.tf` preconditions).

## Variables

Every variable has `description` and `type`. Object types use `optional(type, default)` for defaults inside the object (for example `ecs-service` `containers`, `ecs-service-alarms` thresholds). Lists of things the caller may leave empty default to `[]` or `{}`; feature switches that need a whole block default to `null` (`load_balancer`, `autoscaling`, `proxy`, `access_logs`, `github_immutable_ids`).

Validation is added where a wrong value would otherwise fail late at apply time or silently weaken security (consistent across all 16 modules). Patterns in use:

| Pattern | Example |
| --- | --- |
| Range | `deletion_window_in_days` 7..30 (`kms/variables.tf:34-37`), `max_session_duration` 3600..43200 |
| Enum via `contains` | `cpu_architecture`, `key_algorithm`, `price_class`, capacity providers |
| Regex via `can(regex(...))` | `github_repository`, ARN shapes in `ci-oidc-role`, `hosted_zone_id`, `domain_name`, 12-digit account IDs in `ecr` |
| Uniqueness | container names, rule group names and priorities, backend path patterns, SANs |
| Exactly-one-of | security-group rules need exactly one source (`security-group/variables.tf:48-54`) |
| Null-safe | `var.x == null ? true : ...` or `var.x == null || ...` for optional objects |
| Not empty | `length(var.security_group_ids) > 0` with a reason in the message (`rds-postgres/variables.tf:38-41`) |

Error messages are full sentences that name the variable and the rule ("github_repository must be owner/name without wildcards.").

Checks that need more than one variable or a computed value use `lifecycle { precondition {} }` on the resource instead (`alb` name length ≤ 32, `ecs-service` load balancer container name, `ecr`/`ci-oidc-role` "required when create_* is false", `rds-postgres` proxy roles subset, `cloudfront-spa` aliases need a certificate, `acm-certificate` SAN repeats the domain). `tags` uses `precondition` on an `output`.

## Optional resources and blocks

Optional single resources use `count = <condition> ? 1 : 0` and are read back with `one(resource[*].attr)` or `[0]`. Collections use `for_each` over a map or `toset(list)`. Optional nested blocks use `dynamic` with `for_each = cond ? [1] : []` or `for_each = var.x == null ? [] : [var.x]`. IAM statements that depend on optional inputs are built with `concat(length(list) == 0 ? [] : [{...}], ...)` so an empty list removes the statement (`ci-oidc-role/main.tf:13-82`, `ecs-service/locals.tf:90-129`, `kms/main.tf:41-63`).

## Policies

IAM and resource policies are written with `jsonencode({ Version = "2012-10-17", Statement = [...] })` and named `Sid`s. `vpc/flow_logs.tf` is the only place using `data "aws_iam_policy_document"`. Inline role policies (`aws_iam_role_policy`) are used everywhere; the only managed-policy attachment is `AmazonRDSEnhancedMonitoringRole` (`rds-postgres/main.tf:58-61`).

## Region

Use `data.aws_region.<name>.region`, not `.name` (changed for provider 6, `CHANGELOG.md` `[0.3.0]`, commit `905ac0a`).

## Prose

READMEs, descriptions and the CHANGELOG use Irish/British spelling ("authorisation", "behaviour", "utilisation") and short declarative sentences. Module READMEs follow the same section order: title, one-paragraph summary, `## Owns`, `## Does not own`, optional `## Provider`, `## Usage`, `## Defaults worth knowing`, `## Left out on purpose` or `## Left out of the reference shape`, `## Tests`, `## Example`, then the terraform-docs block.

Placeholders only: account `123456789012`, domains `example.com`/`example.org`/`example.test`, org `example-org`, region `eu-west-1` (and `us-east-1` for CloudFront). Enforced by `scripts/check-no-foreign-identifiers.sh`.
