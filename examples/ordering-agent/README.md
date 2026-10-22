# ordering-agent example

A complete wiring of `ecs-cluster` and `ecs-service` for a service with two containers in one Fargate task:

- `ordering-agent`: public container on port 8788, routed from an ALB listener by host header.
- `ordering-mcp`: sidecar listening on `127.0.0.1:8787`. It has no port mapping, so the load balancer cannot reach it. The agent waits for it to be `HEALTHY` through `depends_on`.
- A DynamoDB table encrypted with a customer-managed KMS key (rotation on), TTL on `expires_at` and point-in-time recovery.
- A task role policy that allows only `GetItem`, `PutItem`, `UpdateItem` and `DeleteItem` on that table, and `Encrypt`, `Decrypt` and `GenerateDataKey` on that key.

VPC, subnets, listener, ALB security group, registry host and secret names are placeholders. The secrets (`.../llm-AbCdEf`, `.../ordering-GhIjKl`) must already exist in Secrets Manager; Terraform does not create them.

```
terraform init
terraform plan -var vpc_id=vpc-... -var 'private_subnet_ids=["subnet-..."]'
```

After the first apply, deploy real images with the `ecs-service-deploy` workflow using the outputs `cluster_name`, `service_name` and `task_definition_family`. Container names in the workflow `images` input must be `ordering-agent` and `ordering-mcp`.
