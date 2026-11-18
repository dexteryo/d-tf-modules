# Testing

> Generated 2026-10-31 (INIT) from `v0.5.1`.

## Strategy

Every module and the composed example carry a native `terraform test` suite that runs without AWS credentials. There are no Terratest/Go tests, no Kitchen, no integration tests against a real account and no coverage tooling. Static checks (fmt, validate, TFLint, Trivy, terraform-docs drift) and a shell test for the identifier guard complete the gate (`scripts/check.sh`).

| Suite | Runs (`^run` blocks) |
| --- | --- |
| `modules/acm-certificate/tests/acm-certificate.tftest.hcl` | 20 |
| `modules/alb/tests/alb.tftest.hcl` | 13 |
| `modules/ci-oidc-role/tests/ci_oidc_role.tftest.hcl` | 18 |
| `modules/cloudfront-spa/tests/cloudfront-spa.tftest.hcl` | 35 |
| `modules/ecr/tests/ecr.tftest.hcl` | 10 |
| `modules/ecs-cluster/tests/ecs_cluster.tftest.hcl` | 5 |
| `modules/ecs-service/tests/ecs_service.tftest.hcl` | 21 |
| `modules/ecs-service-alarms/tests/ecs_service_alarms.tftest.hcl` | 7 |
| `modules/kms/tests/kms.tftest.hcl` | 6 |
| `modules/rds-postgres/tests/rds_postgres.tftest.hcl` | 13 |
| `modules/s3-bucket/tests/s3_bucket.tftest.hcl` | 10 |
| `modules/security-group/tests/security_group.tftest.hcl` | 7 |
| `modules/sns-topic/tests/sns_topic.tftest.hcl` | 6 |
| `modules/tags/tests/tags.tftest.hcl` | 7 |
| `modules/vpc/tests/vpc.tftest.hcl` | 11 |
| `modules/waf-web-acl/tests/waf-web-acl.tftest.hcl` | 18 |
| `examples/ordering-agent/tests/ordering_agent.tftest.hcl` | 2 |
| `tests/check-no-foreign-identifiers.test.sh` | shell, plants strings and expects failure or success per case |

## How a suite is written

Every provider-using suite starts with `mock_provider "aws"`, either empty (`mock_provider "aws" {}`) or with `mock_data` / `mock_resource` blocks that give computed attributes realistic values so downstream expressions work:

```hcl
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/mock/0123456789abcdef"
      arn_suffix = "app/mock/0123456789abcdef"
    }
  }
}
```

Typical mocks: `aws_caller_identity.account_id`, `aws_region.region`, `aws_ec2_managed_prefix_list.id`, ARNs of `aws_kms_key`, `aws_iam_role`, `aws_lb`, `aws_lb_listener`, `aws_lb_target_group`, `aws_cloudfront_distribution`, `aws_cloudwatch_log_group`. `tags` has no provider and needs no mock.

Per-run overrides use `override_resource { target = ..., values = {...} }` where one run needs a different computed value; this appears in `acm-certificate` (to supply `domain_validation_options`) and `ecs-service`.

A file-level `variables {}` block holds the minimum valid inputs (placeholder IDs such as `vpc-0123456789abcdef0`, `sg-0123456789abcdef0`, account `123456789012`); each `run` overrides only what it tests.

## plan vs apply

Across the suites there are 110 runs with `command = apply` and 99 with `command = plan`. Because the provider is mocked, `apply` creates nothing; it is used when an assertion needs computed attributes from mocks (ARNs, IDs, rule contents). `plan` is used for pure input/output logic and for every negative test. `tags` uses `plan` throughout.

## Negative tests

Validation and preconditions are tested with `expect_failures`, one run per rule:

- `expect_failures = [var.<name>]` for variable validation (for example `var.github_repository`, `var.cidr_block`, `var.backends`, `var.static_site_kms_key_arns`).
- `expect_failures = [<resource>]` for lifecycle preconditions (`aws_lb.this`, `aws_iam_role.this`, `aws_ecr_repository.this`, `aws_db_proxy.this`, `aws_cloudfront_distribution.this`, `aws_acm_certificate.this`, `aws_lb_listener_rule.header_forward`).
- `expect_failures = [output.all_tags]` for the output preconditions of `tags`.

## Naming and assertions

Run names are sentences in snake case that state the behaviour: `no_rules_and_no_outbound_traffic_by_default`, `name_is_built_from_the_inputs`, `header_rule_for_an_unknown_listener_is_refused`. Each `assert` has an `error_message` that states the expectation as a rule ("A security group without rules must not open anything."). Security properties are asserted directly on resource attributes (closed groups, TLS policy, trust subject strings, absent statements when inputs are empty).

## The composed example test

`examples/ordering-agent/tests/ordering_agent.tftest.hcl` applies the whole composition under `mock_provider "aws"` with mocks for every ARN the wiring needs. Its stated purpose is "to prove the modules fit together (no dependency cycle between the load balancer group and the task group)" (`examples/ordering-agent/README.md`).

## Running

```bash
# one module
cd modules/<name> && terraform init -backend=false -input=false && terraform test -no-color

# everything (what CI runs)
scripts/check.sh
```

`terraform init` downloads the AWS provider (about 6.70.x) the first time; `scripts/check.sh` points `TF_PLUGIN_CACHE_DIR` at one temp dir so the download is shared across folders (`scripts/check.sh:7`). See `development-workflow.md` for the result of a local run.

## Expectations for new work

Observed in every module added since v0.2.0, and in the CHANGELOG entry for v0.2.0 ("A `terraform test` suite with `mock_provider "aws"` and an `examples/basic` configuration in every module"): a new module ships with its suite and its basic example, every validation gets a negative run, and security-relevant defaults get a positive assertion.
