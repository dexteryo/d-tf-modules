# Architecture

> Generated 2026-10-31 (INIT). Diagrams are drawn from `README.md` ("How the pieces fit"), `examples/ordering-agent/main.tf` and the `examples/basic/main.tf` of `cloudfront-spa` and `rds-postgres`.

## Style

A flat library of leaf modules composed by the caller. Each module owns one AWS concern, takes everything it depends on as an input (IDs, ARNs, keys) and exposes what others need as outputs. Modules do not look up resources they do not own: the VPC, subnets, keys, hosted zone, certificate and OIDC provider all arrive as inputs (each README's "Does not own" section). Only `alb` → `security-group` and `ecr` → `kms` are nested calls (`modules/alb/main.tf:38`, `modules/ecr/main.tf:35`).

Confidence: Verified.

## Cross-cutting inputs

```mermaid
flowchart LR
  tags[tags<br/>all_tags] -->|tags| every[every other module]
  kms[kms<br/>kms_key_arn] -->|kms_key_arn| ecr
  kms -->|kms_key_arns, log_kms_key_arn| ecs-service
  kms -->|kms_key_arn| sns-topic
  kms -->|kms_key_arn| s3-bucket
  kms -->|logs_kms_key_arn| vpc
  kms -->|data_kms_key_arn, logs_kms_key_arn| rds-postgres
  kms -->|kms_key_arn, us-east-1| waf-web-acl
  kms -->|access_logs.kms_key_arn, us-east-1| cloudfront-spa
  kms -->|execute_command_*_kms_key_arn| ecs-cluster
```

`tags` is the only module with no provider. Its `all_tags` output is passed as `tags` everywhere (`modules/tags/outputs.tf:1-14`); every resource-creating module then adds `Name` with `merge(var.tags, { Name = ... })`.

`kms` is called once per purpose with a `name_suffix` (for example `app`, `sessions`, `alarms` in `examples/ordering-agent/main.tf:30-74`). The key policy has to admit the service that will use it. The examples do this through `service_grants`: `logs.<region>.amazonaws.com` scoped by `kms:EncryptionContext:aws:logs:arn`, `cloudwatch.amazonaws.com` for an alarm topic, `cloudfront.amazonaws.com` scoped by `aws:SourceArn` for a static-site bucket.

## ECS service composition

```mermaid
flowchart TD
  vpc[vpc or caller's VPC] -->|vpc_id, subnet ids| sg_alb
  subgraph alb_mod[alb]
    sg_alb[security-group<br/>name_suffix=alb] --> lb[aws_lb + HTTPS listeners<br/>default 403]
  end
  vpc -->|vpc_id| sg_task[security-group<br/>task group]
  lb -->|alb_security_group_id| sg_task
  sg_task -->|security_group_id via egress_rules| sg_alb
  lb -->|listener_arns key| svc[ecs-service]
  sg_task -->|security_group_ids| svc
  cluster[ecs-cluster] -->|cluster_arn| svc
  ecr[ecr] -. image URL in containers .-> svc
  svc -->|target_group_arn| lb
  svc -->|service_name, target_group_arn_suffix| alarms[ecs-service-alarms]
  cluster -->|cluster_name| alarms
  lb -->|alb_arn_suffix| alarms
  topic[sns-topic] -->|topic_arn as alarm_actions| alarms
  svc -->|service_arn, execution_role_arn, task_role_arn| role[ci-oidc-role]
  ecr -->|repository_arn| role
```

The load balancer group and the task group reference each other: the task group admits the ALB group on the container port, the ALB group lists the task group as egress (`README.md` "How the pieces fit"; `examples/ordering-agent/main.tf:150-185`). There is no dependency cycle because rules are separate `aws_vpc_security_group_*_rule` resources, which the example's test proves (`examples/ordering-agent/README.md`).

`alb` with `cloudfront_only = true` plus a `header_forward_rules` entry carrying a random secret header is the pattern for "only my CloudFront distribution may reach this origin" (`modules/alb/variables.tf:71-75`, `examples/ordering-agent/main.tf:130-148`). `ecs-service` adds its own listener rule by host header or path pattern; the ALB's default action stays 403.

## Three-tier web composition

```mermaid
flowchart TD
  acm[acm-certificate<br/>provider us-east-1] -->|certificate_arn| cf
  waf[waf-web-acl<br/>provider us-east-1] -->|web_acl_arn| cf[cloudfront-spa<br/>provider us-east-1]
  bucket[s3-bucket] -->|bucket_regional_domain_name| cf
  cf -->|distribution_arn| bucket
  cf -. backends: VPC origin to an internal ALB .-> api[internal ALB + ecs-service]
  vpc[vpc] -->|isolated_subnet_ids| db[rds-postgres]
  vpc -->|vpc_id| sgdb[security-group: db, proxy, app]
  sgdb -->|security_group_ids, proxy.security_group_ids| db
  vpc -->|private_subnet_ids| api
```

The bucket ↔ distribution mutual reference works because the bucket policy is its own resource (`modules/s3-bucket/main.tf:114-122`) and the distribution only needs the bucket's domain name (`modules/cloudfront-spa/examples/basic/main.tf`). `cloudfront-spa` does not create the VPC origin itself; it takes `vpc_origin_id` per backend (`modules/cloudfront-spa/variables.tf:84-101`).

The `vpc` module's subnet tiers map to roles: public (NAT gateways, external load balancers), private (tasks and interface endpoints, routed out through the NAT of their zone), isolated (databases, no route out) (`modules/vpc/outputs.tf:16-29`). Layout is fixed for a `/16`: for zone `i`, public is `cidrsubnet(cidr, 8, i)` (a `/24`), isolated is `cidrsubnet(cidr, 8, 10 + i)` (a `/24`) and private is `cidrsubnet(cidr, 6, 4 + i)` (a `/22`) (`modules/vpc/main.tf:7-9`).

## Runtime ownership split with d-github-actions

```mermaid
sequenceDiagram
  participant TF as Terraform (these modules)
  participant AWS as ECS service
  participant GH as d-github-actions workflow
  TF->>AWS: create cluster, service, task definition (bootstrap image), roles
  Note over TF,AWS: ignore_changes = [task_definition, desired_count]
  GH->>GH: build once, scan, push by digest (ci-oidc-role)
  GH->>AWS: register task definition revision with digests, update service
  GH->>AWS: promote the same digests to the next environment
  TF->>AWS: later applies change CPU, memory, roles, ports, secrets only
```

Source: `README.md` steps 1-3 and `modules/ecs-service/main.tf:91-141`. Autoscaling, when set, owns desired count after creation (`modules/ecs-service/main.tf:191-238`).

## What lives outside the library

Hosted zones, OIDC provider (unless `create_oidc_provider = true` in exactly one role), VPC origins, application secrets referenced by `ecs-service` containers, database roles inside PostgreSQL (`rds-postgres` only creates their Secrets Manager secrets, `modules/rds-postgres/variables.tf:143-149`), ALB access-log buckets and policies, and Lambda.
