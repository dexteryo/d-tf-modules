# Security

> Generated 2026-10-31 (INIT) from `v0.5.1`. These are the controls the modules build in by default; a caller can still weaken some through inputs, and that is noted where it applies.

## Encryption at rest (KMS)

Every module that stores data takes a customer-managed key ARN or creates one. None falls back silently to an AWS-managed key.

| Module | Key input | Default behaviour |
| --- | --- | --- |
| `kms` | n/a | `enable_key_rotation = true` always (`modules/kms/main.tf:93`); deletion window 30 days, validated 7..30 |
| `s3-bucket` | `kms_key_arn` (required, `nullable = false`) | SSE-KMS with bucket key (`modules/s3-bucket/main.tf:47-57`) |
| `ecr` | `create_kms_key` (default true) or `kms_key_arn` | `encryption_type = "KMS"`; precondition forces a key when `create_kms_key = false` (`modules/ecr/main.tf:54-64`) |
| `sns-topic` | `kms_key_arn` (required) | description warns that `aws/sns` cannot be used because CloudWatch must publish (`modules/sns-topic/variables.tf:23-26`) |
| `vpc` | `logs_kms_key_arn` (required) | flow log group encrypted |
| `rds-postgres` | `data_kms_key_arn`, `logs_kms_key_arn` (required) | storage, Performance Insights, master secret and role secrets use the data key; log groups use the logs key (`modules/rds-postgres/main.tf:73-97`, `roles.tf:12`) |
| `waf-web-acl` | `kms_key_arn` (required, us-east-1) | WAF log group encrypted |
| `cloudfront-spa` | `access_logs.kms_key_arn` | only when access logs are on |
| `ecs-service` | `log_kms_key_arn`, `kms_key_arns` | optional (default `null` / `[]`): the service log group is encrypted only if the caller passes a key |
| `ecs-cluster` | `execute_command_kms_key_arn`, `execute_command_log_kms_key_arn` | optional, only used with ECS Exec logging |

The KMS key policy (`modules/kms/main.tf:27-88`) is built from named inputs. With `enable_iam_policy_delegation = true` (default) the account root gets `kms:*` so IAM policies can grant use; with it off, root only administers and use is limited to `encrypt_principals`, `decrypt_principals` and `service_grants`. `service_grants` support a single condition, which the examples use to scope CloudWatch Logs to a log-group ARN and CloudFront to `aws:SourceArn`.

## Encryption in transit

- S3 bucket policy denies `aws:SecureTransport = false` (`modules/s3-bucket/main.tf:13-20`).
- RDS parameter group sets `rds.force_ssl = 1` and `ssl_min_protocol_version = TLSv1.2`; RDS Proxy `require_tls = true` with SCRAM-SHA-256 (`modules/rds-postgres/main.tf:17-25`, `proxy.tf:58-66`).
- ALB listeners are HTTPS only, default policy `ELBSecurityPolicy-TLS13-1-2-2021-06` (`modules/alb/main.tf:86`, `variables.tf:109`).
- CloudFront redirects viewers to HTTPS (`https-only` on backend paths), minimum `TLSv1.2_2021` with a custom certificate, HSTS two years with subdomains and preload (`modules/cloudfront-spa/main.tf`).
- SNS HTTPS subscriptions must start with `https://` (`modules/sns-topic/variables.tf:45-48`).

## Network exposure

- `security-group` creates no rules unless given, and egress defaults to nothing ("The default is no outbound traffic at all", `modules/security-group/variables.tf:63`). Each rule needs exactly one source or destination.
- `vpc` manages the default security group with no rules, which empties it (`modules/vpc/main.tf:20-24`); public subnets have `map_public_ip_on_launch = false`; isolated subnets have no route out.
- `alb` security group is closed until `cloudfront_only`, `ingress_cidrs` or `ingress_prefix_list_ids` is set; every listener without `default_target_group_arn` answers a fixed 403; invalid header fields are dropped and deletion protection is on by default (`modules/alb/variables.tf:44-54`, `main.tf:100-112`). The header-forward rule values are `sensitive` (`variables.tf:126-131`) and the output exposing them is `sensitive`.
- `ecs-service`: `assign_public_ip = false` default; the module creates no security group and requires at least one (`modules/ecs-service/variables.tf:21-35`).
- `rds-postgres`: `publicly_accessible = false`; requires at least one security group "or RDS falls back to the VPC default group" (`variables.tf:34-42`).
- S3: all four Block Public Access flags on, `BucketOwnerEnforced` ownership (`modules/s3-bucket/main.tf:59-73`). CloudFront read is only by `cloudfront.amazonaws.com` with `AWS:SourceArn` equal to the given distribution.

## Identity and least privilege

### GitHub OIDC deploy role (`modules/ci-oidc-role`)

The trust policy allows `sts:AssumeRoleWithWebIdentity` only with `StringEquals` on both `token.actions.githubusercontent.com:aud = sts.amazonaws.com` and `:sub` equal to one exact subject (`modules/ci-oidc-role/main.tf:106-119`):

- `repo:<owner>/<name>:environment:<environment>` by default;
- `repo:<owner>@<owner_id>/<name>@<repository_id>:environment:<environment>` when `github_immutable_ids` is set (v0.5.1), which "a recreated or renamed repository cannot reuse" (`variables.tf:33-45`).

`github_repository` and `github_environment` reject wildcards by regex. The GitHub environment defaults to the Terraform `environment`; its protection rules are described as "the deploy gate" (`variables.tf:48`).

Permissions are added only for the lists the caller fills: ECR push/read on listed repositories, `ecs:RegisterTaskDefinition`/`DescribeTaskDefinition` on `*` (the action does not support resource scoping) plus `UpdateService`/`DescribeServices` on listed services, `iam:PassRole` on listed roles conditioned on `iam:PassedToService = ecs-tasks.amazonaws.com`, S3 list/put/delete on listed static-site buckets, `kms:Decrypt`/`GenerateDataKey` on listed keys, CloudFront invalidation on listed distributions. ARNs for the static-site inputs are validated to refuse wildcards, KMS aliases and bare distribution IDs (`variables.tf:88-119`). `ecr:GetAuthorizationToken` on `*` is always present. Optional `permissions_boundary_arn`; session 1 hour by default.

### ECS roles (`modules/ecs-service/iam.tf`, `locals.tf`)

Both roles trust `ecs-tasks.amazonaws.com` with `aws:SourceAccount` equal to the current account. The execution role may write only to its own log group, pull only from the ECR repositories parsed out of the container image URLs (plus `extra_ecr_repository_arns`), read only the Secrets Manager secrets and SSM parameters referenced in `containers[*].secrets` (plus `extra_execution_secret_arns`), and decrypt only `kms_key_arns`. The task role gets nothing unless `task_role_policy_json` is given; ECS Exec adds only the four `ssmmessages` actions.

### Other roles

- `vpc` flow-log role writes only to its own log group (`modules/vpc/flow_logs.tf:20-25`).
- `rds-postgres` proxy role reads only the secrets of the roles listed in `proxy.role_names`, and decrypts with the data key only via Secrets Manager (`kms:ViaService`) (`modules/rds-postgres/proxy.tf:25-48`).
- `sns-topic` lets CloudWatch publish only with `aws:SourceAccount` equal to the account (`modules/sns-topic/main.tf:6-18`).
- `ecr` cross-account pull is opt-in through 12-digit account IDs; no repository policy otherwise.

## Secrets

- RDS master password: `manage_master_user_password = true`, stored by RDS in Secrets Manager under the data key. Application role passwords: `random_password` (40 chars) in one Secrets Manager secret per role, 7-day recovery window (`modules/rds-postgres/roles.tf`). These values live in Terraform state.
- `ecs-service` never takes secret values, only ARNs (`containers[*].secrets` maps env var name to ARN).
- WAF logs redact `authorization` and `cookie` headers, the URI path and the query string by default, and keep 7 days because "They hold client IPs" (`modules/waf-web-acl/variables.tf:29-33,71-87`).

## Data protection

`s3-bucket` versioning is always on; optional compliance-mode Object Lock (`object_lock_retention_days`), whose description warns it "cannot be shortened or removed by anyone, including the account root". `rds-postgres` defaults: `deletion_protection = true`, final snapshot taken, 7-day backups, IAM database authentication enabled, Performance Insights encrypted. `kms` keys have a 30-day deletion window. ECR tags are immutable by default and scanned on push.

## Edge

`cloudfront-spa` sets a strict default Content-Security-Policy (`'self'` everywhere, `frame-ancestors 'none'`, `object-src 'none'`), `X-Frame-Options: DENY`, `nosniff`, `strict-origin-when-cross-origin` (`modules/cloudfront-spa/main.tf:26-56`, `variables.tf:47-51`). The CSP has `override = false`, so an origin's own header wins. `waf-web-acl` defaults to four AWS managed groups (IP reputation, anonymous IP, known bad inputs, common rule set) and a per-IP rate limit of 1000 per 5 minutes that blocks.

## Static scanning and its exceptions

Trivy scans the repository for HIGH and CRITICAL misconfigurations and fails the build on any (`scripts/check.sh`, step "trivy config"). `.trivyignore` holds exactly one entry:

| ID | Stated reason |
| --- | --- |
| `AWS-0053` (publicly exposed load balancer) | "The alb module is the external load balancer by design: its security group is closed unless an ingress option is set (CloudFront prefix list, CIDRs or prefix lists), and every listener answers 403 without a rule; documented in modules/alb/README.md" |

`AWS-0104` (open egress) used to be ignored and was removed in v0.2.0 because "open egress now lives in the caller that asks for it" (`CHANGELOG.md` `[0.2.0]`). The `s3-bucket` README notes Trivy's access-logging finding is below the HIGH threshold.

## Foreign-identifier guard

`scripts/check-no-foreign-identifiers.sh` keeps the public library free of other organisations' identifiers. It scans every tracked and untracked-but-not-ignored file (or given paths) and fails on:

- any token, or run of up to three adjacent tokens joined together, whose SHA-256 of the lower-cased text is in `scripts/foreign-identifiers.sha256` (20 entries; hashed "so the list does not publish what it forbids", `README.md`);
- any 12-digit number other than `123456789012` (repeated-digit numbers excepted);
- any email address outside `example.com`, `example.org`, `example.test`, `users.noreply.github.com` (and `git@github.com`).

It skips `.clever`, `.git`, `.terraform`, lock files, binary files and files over 2 MB. `--git` also scans commit authors, committers and messages (terms and account numbers only, not emails). `tests/check-no-foreign-identifiers.test.sh` plants a canary term (also upper-cased and split by separators), an account number and a foreign email domain and proves the guard fails; checks that placeholders pass, that the report never prints the denied term, that the default list holds only SHA-256 digests, and that the repository itself is clean. Both run in CI and in pre-commit.

Because `.clever` is skipped, nothing in these steering files is checked by the guard.
