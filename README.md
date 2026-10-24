# d-tf-modules

Small, single-purpose Terraform modules for running services on ECS Fargate. Each module owns one thing, takes tags from one place and is built to be composed.

| Module | Owns |
| --- | --- |
| [`modules/tags`](modules/tags) | Mandatory, optional and custom tags; the `all_tags` map every other module takes |
| [`modules/kms`](modules/kms) | One rotating KMS key and alias with a key policy built from named inputs |
| [`modules/ecr`](modules/ecr) | One immutable, scanned, encrypted repository with a lifecycle policy |
| [`modules/security-group`](modules/security-group) | One security group whose rules are inputs; closed by default |
| [`modules/ecs-cluster`](modules/ecs-cluster) | Fargate cluster with Container Insights and optional ECS Exec logging |
| [`modules/ecs-service`](modules/ecs-service) | Task definition, service, target group and listener rule, logs, roles, autoscaling. Takes security group ids |
| [`modules/alb`](modules/alb) | External load balancer, its security group, HTTPS listeners, CloudFront-only ingress, header rules |
| [`modules/ecs-service-alarms`](modules/ecs-service-alarms) | CloudWatch alarms for the service and the load balancer in front of it |
| [`modules/sns-topic`](modules/sns-topic) | Encrypted alarm topic with a CloudWatch publish policy and subscriptions |
| [`modules/ci-oidc-role`](modules/ci-oidc-role) | GitHub OIDC deploy role, trusted for one repository and one environment |
| [`examples/ordering-agent`](examples/ordering-agent) | All of the above composed for a two-container service |

Not built yet: `lambda`. The reference lambda module bundles several packaging modes, tracing agents, container and placeholder images, aliases and secret wiring; it is not small. It is the next module once a workload needs it (see [CHANGELOG.md](CHANGELOG.md)).

The companion repository `d-github-actions` builds images, scans them, pushes them to ECR by digest and deploys new task definition revisions to a service created by these modules, promoting the same digest from one environment to the next.

## Requirements

- Terraform `>= 1.6` (the tests need `>= 1.7`; CI uses 1.15.3)
- AWS provider `~> 6.0`
- For development: `tflint`, `terraform-docs`, `trivy`, `shellcheck`, `python3`; optionally `pre-commit`

## How the pieces fit

```text
tags ──► every module (tags = module.tags.all_tags)

kms ──► ecr, ecs-service (kms_key_arns, log_kms_key_arn), sns-topic
security-group ◄──► alb          (service group admits the alb group; alb group lists the service group as egress)
security-group ──► ecs-service   (security_group_ids)
alb ──► ecs-service              (listener_arns[...] -> load_balancer.listener_arn)
ecs-cluster ──► ecs-service, ecs-service-alarms
ecs-service ──► ecs-service-alarms, ci-oidc-role
sns-topic ──► ecs-service-alarms (alarm_actions)
```

Naming is built from inputs: modules that name AWS resources take `name` and `environment` and produce `<name>-<environment>[-<suffix>]`. Resources shared by every environment (image repositories) take only `name`.

1. Terraform creates the cluster, load balancer, security groups and service. It owns CPU, memory, roles, secrets, ports and networking.
2. The service ignores `task_definition` and `desired_count` after creation.
3. The `ecs-promote` workflow builds once, scans, pushes by digest, registers a new task definition revision with those digests and updates the service, then promotes the same digests to the next environment.

Feed the service outputs `service_name`, `task_definition_family`, the cluster output `cluster_name` and the role output `role_arn` into the workflow inputs `service`, `task-definition-family`, `cluster` and `role-to-assume`.

## Getting started

```
cd examples/ordering-agent
terraform init
terraform plan
```

The example uses placeholder VPC, subnet, certificate and registry values. Override them with variables before a real apply.

## Development

Every check runs without AWS credentials:

```
scripts/check.sh
```

It runs `terraform fmt -check`, `init` and `validate` in every module and example, `terraform test` in every module and in the example (`mock_provider "aws"`), `tflint --recursive`, `trivy config` for HIGH and CRITICAL findings, a terraform-docs drift check, the foreign identifier check and `shellcheck`.

`scripts/check-no-foreign-identifiers.sh` fails when a file contains a term from a hashed deny-list (`scripts/foreign-identifiers.sha256`, sha256 of lower-case tokens, so the list does not publish what it forbids), a 12-digit number other than `123456789012`, or an email address outside the example domains. Run it with `--git` to check commit messages and author names too. `tests/check-no-foreign-identifiers.test.sh` plants strings and proves it fails.

Install the hooks with `pre-commit install`; they run `terraform fmt`, `terraform validate`, `tflint`, `terraform-docs` and the identifier check.

## Versioning

Tag releases `vX.Y.Z` and pin consumers with `?ref=vX.Y.Z`. See [CHANGELOG.md](CHANGELOG.md) for what changed and how to migrate.
