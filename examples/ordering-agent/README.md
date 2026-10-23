# ordering-agent example

The same service as in `v0.1.0`, rebuilt from the small modules of `v0.2.0`. Every module is used once; nothing here is specific to one workload except the names.

| Module | What it contributes |
| --- | --- |
| `tags` | the one `all_tags` map passed to every other module |
| `kms` (three times) | the app key (images, secrets, task logs), the session table key and the alarm topic key |
| `ecr` (per image) | `ordering-agent` and `ordering-mcp` repositories using the app key |
| `ecs-cluster` | the Fargate cluster |
| `alb` | the CloudFront-only load balancer, an HTTPS listener that answers 403 by default, an egress rule to the tasks |
| `security-group` | the task group: the agent port from the load balancer group only, HTTPS to the VPC range only |
| `ecs-service` | the two-container task, target group and listener rule, roles, autoscaling |
| `sns-topic`, `ecs-service-alarms` | the encrypted alarm topic and the alarms watching the service and the load balancer |
| `ci-oidc-role` | the role the deploy workflow assumes, trusted for one repository and one GitHub environment |

The DynamoDB table is a plain resource in `main.tf`: a table is workload data, not a shared pattern.

- `ordering-agent`: container on port 8788, routed from the load balancer by host header.
- `ordering-mcp`: sidecar listening on `127.0.0.1:8787`. It has no port mapping, so the load balancer cannot reach it. The agent waits for it to be `HEALTHY` through `depends_on`.
- A task role policy that allows only `GetItem`, `PutItem`, `UpdateItem` and `DeleteItem` on the table, and `Encrypt`, `Decrypt` and `GenerateDataKey` on its key.

VPC, subnets, certificate, OIDC provider, repository and secret names are placeholders. The secrets (`.../llm-AbCdEf`, `.../ordering-GhIjKl`) must already exist in Secrets Manager; Terraform does not create them. The task group only reaches the VPC range, so the VPC needs endpoints for ECR, Secrets Manager, CloudWatch Logs and DynamoDB (or set `vpc_cidr` wider and accept the egress that implies).

```
terraform init
terraform plan -var vpc_id=vpc-... -var 'private_subnet_ids=["subnet-..."]'
```

`terraform test` plans nothing against AWS: it applies the whole composition with `mock_provider "aws"` to prove the modules fit together (no dependency cycle between the load balancer group and the task group).

After the first apply, deploy real images with the `ecs-promote` or `ecs-service-deploy` workflow of `dex-github-actions` using the outputs `cluster_name`, `service_name`, `task_definition_family` and `deploy_role_arn`. Container names in the workflow `images` input must be `ordering-agent` and `ordering-mcp`.
