# Tech

> Generated 2026-10-31 (INIT) from `main` = `6c52410` (`v0.5.1`).

## Language and providers

The repository is HCL (Terraform) plus two Bash scripts with an embedded Python scanner and one CloudFront Function in JavaScript (`modules/cloudfront-spa/functions/spa-rewrite.js`, runtime `cloudfront-js-2.0`).

Version constraints, exactly as written in every `versions.tf`:

| Scope | `required_version` | `hashicorp/aws` | `hashicorp/random` |
| --- | --- | --- | --- |
| `modules/tags` | `>= 1.6` | none (no provider) | none |
| `modules/rds-postgres` | `>= 1.6` | `~> 6.0` | `~> 3.6` |
| `examples/ordering-agent` | `>= 1.6` | `~> 6.0` | `~> 3.6` |
| every other module (`acm-certificate`, `alb`, `ci-oidc-role`, `cloudfront-spa`, `ecr`, `ecs-cluster`, `ecs-service`, `ecs-service-alarms`, `kms`, `s3-bucket`, `security-group`, `sns-topic`, `vpc`, `waf-web-acl`) | `>= 1.6` | `~> 6.0` | none |

The README adds that "the tests need `>= 1.7`" (`README.md:31`), which matches the `mock_provider` / `override_resource` features the tests use. That floor is not encoded in any `versions.tf`.

History of the provider constraint: `~> 5.0` up to v0.2.1 (`ci-oidc-role` was `>= 5.81, < 6.0`), `~> 6.0` from v0.3.0 (`CHANGELOG.md` `[0.3.0]`, commit `5a123a3`).

No module declares `configuration_aliases`. Region-bound modules (`waf-web-acl`, `cloudfront-spa`, and `acm-certificate` when used for CloudFront) expect the caller to pass `providers = { aws = aws.us_east_1 }` (module READMEs, section "Provider").

Lock files: `examples/ordering-agent/.terraform.lock.hcl` is committed; `modules/**/.terraform.lock.hcl` is git-ignored (`.gitignore`). terraform-docs output in every module README records `aws | 6.70.0` as the resolved provider at generation time.

## Tooling

| Tool | Version pin | Where |
| --- | --- | --- |
| Terraform (CI) | `1.15.3` | `.github/workflows/ci.yml` via `hashicorp/setup-terraform@dfe3c3f…` (v4.0.1) |
| TFLint | latest from `terraform-linters/setup-tflint@6ffdbaa…` (v6.3.2); AWS ruleset `0.38.0`, terraform plugin preset `recommended` | `.github/workflows/ci.yml`, `.tflint.hcl` |
| Trivy | `v0.76.1` via `aquasecurity/setup-trivy@81e5143…` (v0.3.1) | `.github/workflows/ci.yml` |
| terraform-docs | `v0.24.0`, tarball checked against a pinned SHA-256 | `.github/workflows/ci.yml` |
| shellcheck | runner's system package | `scripts/check.sh` last step |
| python3 | runner's system interpreter, run with `-I` | `scripts/check-no-foreign-identifiers.sh:100` |
| pre-commit | `antonbabenko/pre-commit-terraform` `v1.96.2` | `.pre-commit-config.yaml` |

GitHub Actions are pinned by full commit SHA with the version in a trailing comment (`.github/workflows/ci.yml`).

## AWS services covered

KMS, IAM (roles, inline policies, OIDC provider), EC2/VPC (subnets, NAT, endpoints, flow logs, security groups), ELBv2, ECS Fargate, Application Auto Scaling, ECR, CloudWatch Logs and alarms, SNS, S3, RDS PostgreSQL and RDS Proxy, Secrets Manager, WAFv2, CloudFront (distribution, OAC, functions, response headers policy, VPC origins, log delivery), ACM and Route 53 records. Each is visible as `resource` blocks in the corresponding module's `main.tf` (or split files).

Defaults that pin product versions: `rds-postgres` `engine_version = "17"` and `instance_class = "db.t4g.medium"` (`modules/rds-postgres/variables.tf:60-70`); ALB listener TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06` (`modules/alb/variables.tf:109`); CloudFront minimum protocol `TLSv1.2_2021` (`modules/cloudfront-spa/main.tf:149`).

## Local environment observed on 2026-10-31

`terraform` 1.15.3 and `python3` are installed (nix profile). `tflint`, `trivy`, `terraform-docs`, `shellcheck` and `pre-commit` are not on the PATH, so `scripts/check.sh` cannot complete locally on this machine (see `development-workflow.md`).
