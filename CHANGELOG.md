# Changelog

All notable changes to this repository are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `modules/s3-bucket`: private bucket with KMS encryption, versioning, Block Public Access, TLS-only policy, optional compliance-mode Object Lock and optional CloudFront origin access control read access.
- `modules/vpc`: three-tier VPC over 2 to 6 zones with a NAT gateway and Elastic IP per zone, S3 and interface endpoints, KMS-encrypted flow logs and an emptied default security group.
- `modules/rds-postgres`: encrypted, private, TLS-only PostgreSQL instance with a managed administrator secret, generated credentials per application role, PostgreSQL logs, a free-storage alarm and an optional RDS Proxy.

### Changed

- `modules/s3-bucket`: `name` must not be empty, `kms_key_arn` no longer accepts null (it would have fallen back to the AWS-managed key), and the two lifecycle day inputs must be at least 1.
- **Breaking:** every module now requires the AWS provider `~> 6.0` (was `~> 5.0`; `ci-oidc-role` was `>= 5.81, < 6.0`). Callers on 5.x must upgrade the provider before taking this version.
- CI runs Terraform 1.15.3 (was 1.8.3).

## [0.2.1] - 2026-10-23

Repository renamed; references updated; no functional change.

## [0.2.0] - 2026-10-23

The shared library is split into small, single-purpose modules, so that a workload composes the pieces it needs instead of taking one large module.

### Added

- `modules/tags`: mandatory (`Environment`, `Service`, `Repository`, `ManagedBy`), optional and custom tags validated in one place; output `all_tags` is passed to the `tags` input of every other module.
- `modules/kms`: rotating key and alias, key policy from named inputs (management, encrypt and decrypt principals, service grants with conditions, extra statements).
- `modules/ecr`: immutable, scanned, KMS-encrypted repository with a lifecycle policy and an optional pull policy for other accounts; creates its own key through `../kms` unless `create_kms_key = false`.
- `modules/security-group`: one group whose ingress and egress rules are inputs; closed by default.
- `modules/alb`: external application load balancer with its own security group, `cloudfront_only`, CIDR and prefix list ingress, HTTPS listeners that answer 403 by default, and header-based forwarding rules.
- `modules/ecs-service-alarms`: CPU, memory, desired-versus-running, deployment count and running-task alarms, plus target 5xx and healthy host alarms when a load balancer is given.
- `modules/sns-topic`: encrypted topic, CloudWatch publish policy and email or HTTPS subscriptions.
- `modules/ci-oidc-role`: GitHub OIDC deploy role whose trust is the exact `repo:<owner>/<name>:environment:<environment>` subject, with ECR push, ECS deploy and `iam:PassRole` limited to the listed resources.
- A `terraform test` suite with `mock_provider "aws"` and an `examples/basic` configuration in every module.
- `scripts/check.sh` (all checks), `scripts/check-no-foreign-identifiers.sh` with its test, a CI workflow and pre-commit hooks for both.

### Changed

- `modules/ecs-service` is service-only: task definition, service, target group and listener rule, log group, roles and autoscaling. It no longer creates security groups or rules.
- `modules/ecs-cluster` names the cluster `<name>-<environment>` and takes tags from the tags module.
- `examples/ordering-agent` is rebuilt from the small modules.
- `.trivyignore` no longer ignores `AWS-0104`; open egress now lives in the caller that asks for it. It ignores `AWS-0053` for the external load balancer, justified in `modules/alb/README.md`.

### Removed

- `modules/ecs-service`: input `vpc_id` (the target group takes `load_balancer.vpc_id`), `load_balancer.alb_security_group_id`, output `security_group_id`, and the resources `aws_security_group.this`, `aws_vpc_security_group_ingress_rule.from_alb` and `aws_vpc_security_group_egress_rule.all`.
- `modules/ecs-service` and `modules/ecs-cluster` no longer add the tags `Environment`, `Service` and `ManagedBy`; they add `Name` and pass through the `tags` input.

### Migration from v0.1.0

1. Add a `tags` module call and pass `module.tags.all_tags` as `tags` everywhere. Tags that v0.1.0 added itself now come from the module.
2. `ecs-cluster`: the cluster is named `<name>-<environment>`. To keep the name `ordering-integration`, set `name = "ordering"` and `environment = "integration"`.
3. `ecs-service`:
   - Create the task security group with `modules/security-group` (an ingress rule from the load balancer group on the container port, and the egress you need) and pass `security_group_ids = [module.task_security_group.security_group_id]`.
   - Remove `vpc_id` and `load_balancer.alb_security_group_id`; add `load_balancer.vpc_id`.
   - Replace `module.service.security_group_id` with the id of your security group module.
4. Security groups are now named with a prefix (`<name>-<environment>-`) so a replacement can be created before the old group is destroyed. Applying over a live v0.1.0 stack replaces the group; nothing is replaced if you start from a fresh state.
5. Resource addresses change (a security group moves from `module.service` to its own module call). Use `moved` blocks or `terraform state mv` for a live stack. The `ordering` stack in `clevercards-ai-tools` was never applied and lists its address changes in `terraform/ordering/README.md`.
6. Pin `?ref=v0.2.0`.

## [0.1.0] - 2026-10-23

### Added

- `modules/ecs-cluster`: ECS cluster with Container Insights, `FARGATE` and `FARGATE_SPOT` capacity providers, optional encrypted ECS Exec logging.
- `modules/ecs-service`: Fargate service with task definition, security group, ALB target group and listener rule, per-service log group, least-privilege execution and task roles, autoscaling, and Terraform ignoring task definition and desired count changes by default.
- `examples/ordering-agent`: two-container task (agent behind an ALB, MCP sidecar on loopback) with a customer-managed-KMS DynamoDB table.
- `terraform test` suites using `mock_provider "aws"`; they need no AWS credentials.
