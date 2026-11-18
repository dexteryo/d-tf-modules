# Operations

> Generated 2026-10-31 (INIT). This repository is a library: it is never applied on its own, has no state backend, no environments and no deployment pipeline. Operations here means how callers consume it and what runtime behaviour the modules give the stacks built from them.

## Distribution

Modules are consumed from git. The README asks consumers to "pin consumers with `?ref=vX.Y.Z`" (`README.md:83`). The one real caller in the hub, `workspace/finn-app-brazil`, pins harder than that: every `source` uses the full commit hash of the release with the tag in a trailing comment, citing checkov `CKV_TF_1` (`finn-app-brazil/infra/README.md:36-47`):

```hcl
source = "git::https://github.com/dexteryo/d-tf-modules.git//modules/kms?ref=6c52410617f5bab670a396157a575ad767f6fd04" # v0.5.1
```

That hash is the commit the annotated tag `v0.5.1` points at (`git rev-parse v0.5.1^{commit}`). The same file says `terraform init` clones the repository over HTTPS with no credential, which implies the GitHub repository is public (Strongly Inferred from that statement; not checked against GitHub).

To bump, the caller replaces hash and comment across all files in one go (`finn-app-brazil/infra/README.md:45-48`).

## Who runs the modules

| Caller | Environments seen | How Terraform runs |
| --- | --- | --- |
| `workspace/finn-app-brazil/infra/envs/nonprod` | `nonprod` only | `.github/workflows/infra.yml` calls the reusable `terraform.yml` of `d-github-actions` with GitHub OIDC roles managed by hand (`finn-app-brazil/infra/README.md`, "How CI uses AWS") |
| `examples/ordering-agent` (this repo) | placeholder `var.environment` | not applied anywhere; tested under `mock_provider` |

## Runtime ownership after apply

`ecs-service` defaults to `manage_task_definition_externally = true`: the service ignores `task_definition` and `desired_count` after creation, and the `d-github-actions` deploy workflows register new revisions and update the service (`README.md` "How the pieces fit"; `modules/ecs-service/main.tf:91-141`). A later `terraform apply` may register a new revision with the bootstrap image, but the service does not move to it (`modules/ecs-service/README.md`, "Bootstrap image"). Switching that variable on a live service destroys and recreates the service.

The deployment circuit breaker is on with rollback by default (`modules/ecs-service/variables.tf:208-215`).

## Observability the modules create

| Signal | Module | Default |
| --- | --- | --- |
| Service logs `/ecs/<name>-<env>` | `ecs-service` | 30 days, `awslogs` driver, stream prefix per container |
| ECS Exec logs `/ecs/<name>-<env>/execute-command` | `ecs-cluster` | off; 30 days when on |
| Container Insights | `ecs-cluster` | enabled |
| Service alarms: CPU > 80 %, memory > 80 %, desired-vs-running ≥ 1, deployments > 1, running < min (off), target 5xx > 5, healthy hosts < 1 | `ecs-service-alarms` | first four on; the last two only with `load_balancer`; CPU and memory treat missing data as not breaching |
| Alarm topic `<name>-<env>-alarms` | `sns-topic` | email (manual confirmation) and HTTPS subscriptions |
| VPC flow logs `/<name>-<env>/vpc-flow` | `vpc` | `ALL` traffic, 365 days |
| PostgreSQL and upgrade logs | `rds-postgres` | 365 days; enhanced monitoring every 60 s; Performance Insights 7 days |
| RDS free-storage alarm | `rds-postgres` | < 5 GiB over 3 × 5 min, missing data breaching, actions on alarm and OK |
| WAF logs `aws-waf-logs-<name>-<env>` | `waf-web-acl` | 7 days, redacted; CloudWatch metrics and sampled requests per rule |
| CloudFront access logs `/aws/cloudfront/<name>-<env>` | `cloudfront-spa` | off; JSON, 7 days when on |
| ALB access logs | `alb` | off; needs a caller-owned bucket |

Thresholds come from `modules/ecs-service-alarms/variables.tf` and `modules/rds-postgres/main.tf:108-124`.

## Recovery and safety defaults

- RDS: `deletion_protection = true`, final snapshot `<identifier>-final` unless skipped, 7-day backups (point-in-time restore window), backup window 05:00-06:00 UTC, maintenance Sunday 06:30-07:30 UTC, auto minor upgrades, gp3 storage autoscaling 20 → 200 GiB. The `db_identifier` output is described as what "the point-in-time restore runbook names" (`modules/rds-postgres/outputs.tf:2`); no runbook is in this repository.
- ALB deletion protection is on by default.
- KMS keys wait 30 days before deletion.
- S3 versioning always on; non-current versions expire after 90 days unless Object Lock is on; incomplete multipart uploads aborted after 7 days.
- ECR: untagged images expire after 7 days, the 30 most recent tagged images are kept.
- Security groups, parameter groups, target groups and certificates use `create_before_destroy`, so replacements are created before the old one is removed.

## Region constraints

CloudFront-scoped resources (`waf-web-acl`, `cloudfront-spa`, its access-log key, and an `acm-certificate` used by CloudFront) must run with a `us-east-1` provider passed by the caller. Load balancer certificates must be in the load balancer's region.

## Not covered

No dashboards, runbooks, on-call configuration, SLOs or cost controls live in this repository. Upgrade procedures exist only as CHANGELOG migration sections (v0.2.0 and v0.3.0).
