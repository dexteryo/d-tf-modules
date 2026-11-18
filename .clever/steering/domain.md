# Domain

> Generated 2026-10-31 (INIT). The "domain" of this repository is AWS infrastructure composition; there are no business entities. This file fixes the vocabulary the modules and their docs use.

## Vocabulary

| Term | Meaning here | Source |
| --- | --- | --- |
| workload / `name` | The service or application a set of resources belongs to; first part of every resource name | every `variables.tf` |
| `environment` | Deployment stage, for example `integration`, `staging`, `production`. Empty means shared by all environments (keys, buckets, repositories) | `kms`, `s3-bucket`, `vpc` variable descriptions |
| `name_suffix` | Last name part when one workload has several of the same thing (`app`, `sessions`, `alarms`, `alb`, `tasks`, `web`, `edge`) | `kms`, `security-group`, `sns-topic`, `cloudfront-spa` |
| full name | `<name>-<environment>[-<name_suffix>]` | `coding-standards.md` |
| mandatory / optional / custom tags | `Environment`, `Service`, `Repository` (+ `ManagedBy`); `Owner`, `CostCentre`, `DataClassification`, `Component`; anything else | `modules/tags` |
| owns / does not own | The resources a module creates vs those it expects as inputs; every module README states both | module READMEs |
| reference shape / left out | An earlier, larger module design this library deliberately trims; each README lists what was left out and why | module READMEs, "Left out of the reference shape" |
| bootstrap image | Image used only so Terraform can create the first task definition; the first deploy replaces it | `modules/ecs-service/README.md` |
| externally managed task definition | Deploys register revisions outside Terraform; the service ignores `task_definition` and `desired_count` | `modules/ecs-service/main.tf:91-141` |
| promote | Deploy the same image digests to the next environment, in `d-github-actions` | `README.md` |
| sidecar | A container without `port`, reachable only on `127.0.0.1` inside the task | `modules/ecs-service/README.md` |
| tiers: public / private / isolated | Subnets with an internet route / NAT route / no route out | `modules/vpc/outputs.tf` |
| CloudFront only | ALB ingress limited to the `com.amazonaws.global.cloudfront.origin-facing` prefix list, paired with a secret header rule | `modules/alb` |
| origin verify header | A random secret header CloudFront adds and the ALB rule requires (`X-Origin-Verify` in the example) | `examples/ordering-agent/main.tf:139-148` |
| backend (cloudfront-spa) | A path served by an internal load balancer through a CloudFront VPC origin | `modules/cloudfront-spa/variables.tf:84-101` |
| database role | An application login whose password the module generates and stores in its own secret; the role itself is created by the caller's bootstrap | `modules/rds-postgres/variables.tf:143-149` |
| trust subject | The exact GitHub OIDC `sub` claim a deploy role accepts | `modules/ci-oidc-role/outputs.tf:16-19` |
| immutable IDs | GitHub numeric owner and repository IDs in the `sub` claim | `modules/ci-oidc-role/variables.tf:33-45` |
| foreign identifier | A name, account number or email from another organisation; must not appear in this repository | `scripts/check-no-foreign-identifiers.sh` |
| `ordering-agent` / `ordering-mcp` | Fictional example workload: an agent container and an MCP sidecar | `examples/ordering-agent` |

## Invariants the modules hold

- One module, one concern. A module that needs another concern takes its ID as input; only `alb` (security group) and `ecr` (KMS key) create one through a nested module call.
- Closed by default: no ingress, no egress, 403 on listeners, private buckets, private databases, no task-role permissions.
- Encrypted by default with customer-managed keys passed in or created.
- Names are deterministic from inputs, so the same call in another account or environment yields predictable names. Global names (S3) append the account ID by default (`modules/s3-bucket/variables.tf:24-28`).
- Empty list inputs remove the related IAM statement or resource rather than producing a wildcard.

## Bounded contexts

| Context | Modules |
| --- | --- |
| Shared foundations | `tags`, `kms` |
| Network | `vpc`, `security-group` |
| Container runtime | `ecr`, `ecs-cluster`, `ecs-service`, `alb` |
| Monitoring | `ecs-service-alarms`, `sns-topic` (and the RDS alarm inside `rds-postgres`) |
| Data | `rds-postgres`, `s3-bucket` |
| Edge | `acm-certificate`, `waf-web-acl`, `cloudfront-spa` |
| Delivery | `ci-oidc-role` (consumed by `d-github-actions` workflows) |

The grouping is this file's; the repository does not name the groups. The membership follows from what each module owns.
