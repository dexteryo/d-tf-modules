# Product

> Generated 2026-10-31 (INIT) from the repository at `main` = `6c52410` (tag `v0.5.1`). Every claim cites a file; anything not cited is marked as inferred.

## What it is

`d-tf-modules` is a library of small, single-purpose Terraform modules for AWS. It holds no root configuration that is meant to be applied as-is; callers pin a module by git ref and compose the pieces they need. The README opens with the purpose: "Small, single-purpose Terraform modules for running services on ECS Fargate. Each module owns one thing, takes tags from one place and is built to be composed." (`README.md:3`).

The scope grew past ECS in v0.3.0, which added "the modules a three-tier web application on AWS needs (network, database, static app bucket, edge and web ACL)" (`CHANGELOG.md`, `[0.3.0]`).

## Modules

| Module | Owns (from `README.md` and each module's `README.md`) | Since |
| --- | --- | --- |
| `tags` | Mandatory, optional and custom tags; `all_tags` output | v0.2.0 |
| `kms` | One rotating key and alias, key policy from named inputs | v0.2.0 |
| `security-group` | One security group whose rules are inputs; closed by default | v0.2.0 |
| `ecr` | One immutable, scanned, KMS-encrypted repository with lifecycle policy | v0.2.0 |
| `alb` | External ALB, its security group, HTTPS listeners (403 default), header rules | v0.2.0 |
| `ecs-cluster` | Fargate cluster, Container Insights, optional ECS Exec logging | v0.1.0 |
| `ecs-service` | Task definition, service, target group, listener rule, logs, roles, autoscaling | v0.1.0 |
| `ecs-service-alarms` | CloudWatch alarms for a service and its load balancer | v0.2.0 |
| `sns-topic` | Encrypted alarm topic, CloudWatch publish policy, subscriptions | v0.2.0 |
| `ci-oidc-role` | GitHub OIDC deploy role trusted for one repository and one environment | v0.2.0 |
| `s3-bucket` | Private, KMS-encrypted, versioned bucket; optional Object Lock and CloudFront read | v0.3.0 |
| `vpc` | Three-tier VPC, NAT per zone, endpoints, flow logs | v0.3.0 |
| `rds-postgres` | Encrypted, private, TLS-only PostgreSQL, per-role secrets, optional RDS Proxy | v0.3.0 |
| `waf-web-acl` | CloudFront web ACL, managed rule groups, rate limit, redacted logs | v0.3.0 |
| `cloudfront-spa` | CloudFront distribution for a SPA from private S3 via OAC, optional VPC-origin backends | v0.3.0 |
| `acm-certificate` | Public ACM certificate validated by DNS in an existing Route 53 zone | v0.4.0 |

`examples/ordering-agent` composes `tags`, `kms`, `ecr`, `ecs-cluster`, `alb`, `security-group`, `ecs-service`, `sns-topic`, `ecs-service-alarms` and `ci-oidc-role` into a two-container service (`examples/ordering-agent/README.md`). It does not use `vpc`, `s3-bucket`, `rds-postgres`, `waf-web-acl`, `cloudfront-spa` or `acm-certificate`.

Not built: a `lambda` module. The README says it is "the next module once a workload needs it" (`README.md:25`).

## Users

The repository owner (GitHub `dexteryo`, `git remote -v`) and the infrastructure code of his projects. Real callers found in the hub workspace on 2026-10-31:

| Caller | Files | Modules used | Pin |
| --- | --- | --- | --- |
| `workspace/finn-app-brazil` | `infra/envs/nonprod/{main,network,kms,security_groups,storage,database,keycloak,api,webhooks,deploy,dns,edge}.tf` | `tags`, `vpc`, `kms` (2 calls), `security-group` (6), `s3-bucket` (3), `rds-postgres`, `ecs-cluster`, `ecs-service` (2), `ecr`, `sns-topic`, `ci-oidc-role`, `acm-certificate` (2), `waf-web-acl` (2), `cloudfront-spa` (2) | full commit hash `6c52410617f5bab670a396157a575ad767f6fd04` with `# v0.5.1` comment |
| `workspace/d-github-actions` | `README.md:90`, `README.md:186`, `CHANGELOG.md:90` | Documentation only: tells callers to create deploy roles with `modules/ci-oidc-role` | n/a |

`finn-app-brazil` does not use `alb` or `ecs-service-alarms`. No other directory under `workspace/` references the repository.

## Companion repository

`d-github-actions` builds images, scans them, pushes them to ECR by digest and deploys new task definition revisions to a service these modules created (`README.md:27`). The hand-off contract is four outputs mapped to workflow inputs: `service_name`, `task_definition_family`, `cluster_name` and `role_arn` feed `service`, `task-definition-family`, `cluster` and `role-to-assume` (`README.md:55`). `ecs-service` exists in its two-resource shape so that those deploys do not fight Terraform (see `domain.md`).

## Business rules the library enforces

- Encryption at rest uses a customer-managed KMS key the caller passes or the module creates; there is no fallback to AWS-managed keys (for example `s3-bucket` refuses a null `kms_key_arn`, `CHANGELOG.md` `[0.3.0]`).
- Network access is closed until the caller opens it (`security-group` has no default rules; `alb` listeners answer 403 without a rule).
- CI deploy roles trust one repository and one GitHub environment exactly; wildcards are refused (`modules/ci-oidc-role/variables.tf:27-31`).
- No identifiers of real accounts, clients or people may appear in the repository (`scripts/check-no-foreign-identifiers.sh`). Placeholders are `123456789012` and `example.com`/`example.org`/`example.test`.
