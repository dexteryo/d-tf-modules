# ecs-service

One ECS Fargate service: task definition, service, target group and listener rule, log group, execution and task roles, optional autoscaling.

Terraform owns the shape of the service. Deploys register new task definition revisions with the `ecs-deploy` action from `d-github-actions`, so by default the service ignores `task_definition` and `desired_count` changes (`manage_task_definition_externally = true`).

## Owns

- `aws_ecs_task_definition`, `aws_ecs_service` and the CloudWatch log group.
- The target group and the listener rule that attaches the service to a listener it is given.
- The execution role and the task role with their inline policies.
- Target tracking autoscaling.

## Does not own

- Security groups or their rules: pass `security_group_ids` (`security-group`).
- The load balancer, its listener, certificates and ingress (`alb`). The service takes a `listener_arn` and attaches a rule to it.
- The cluster (`ecs-cluster`), image repositories (`ecr`), keys (`kms`), alarms (`ecs-service-alarms`) and the deploy role (`ci-oidc-role`).

## Usage

```hcl
module "service" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/ecs-service?ref=v0.2.0"

  name               = "ordering"
  environment        = "integration"
  tags               = module.tags.all_tags
  cluster_arn        = module.cluster.cluster_arn
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [module.task_security_group.security_group_id]
  cpu                = 512
  memory             = 1024

  containers = [{
    name  = "app"
    image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/app:bootstrap"
    port  = 8080
  }]

  load_balancer = {
    container_name = "app"
    container_port = 8080
    vpc_id         = var.vpc_id
    listener_arn   = module.alb.listener_arns["https"]
    host_headers   = ["app.example.com"]
    priority       = 100
  }
}
```

See `examples/ordering-agent` for a two-container task wired to every other module.

## Behaviour worth knowing

- **Bootstrap image.** Terraform needs an image to create the first task definition. Use any existing tag; the first deploy replaces it. Because deploys register revisions outside Terraform, a later `terraform apply` registers a new revision with the bootstrap image but the service does not move to it.
- **Names.** Everything is named `<name>-<environment>`. The task definition family is `<name>-<environment>` (output `task_definition_family`).
- **Read-only root filesystem.** Defaults to `true` per container. Set `read_only_root_filesystem = false` only for a container that must write to its filesystem.
- **Health checks.** Container health checks run inside the task, so use `127.0.0.1` rather than `localhost` (`localhost` can resolve to `::1`, where many servers do not listen). With `default_health_check_path` set, every container that has a `port` and no `health_check` gets `curl -fsS http://127.0.0.1:<port><path>`; the image must contain `curl`.
- **Sidecars.** A container without `port` is never reachable from the load balancer. Containers share one network namespace under `awsvpc`, so a sidecar listening on `127.0.0.1` is reachable by the other containers and by nothing else. Use `depends_on` with `HEALTHY` (needs a `health_check` on the dependency) or `START`.
- **Load balancer.** The target group uses `target_type = "ip"` and lives in `load_balancer.vpc_id`. At least one of `host_headers` or `path_patterns` is required. `health_check_grace_period_seconds` only applies when a load balancer is set. Open the container port to the load balancer in the group you pass in `security_group_ids`.
- **Two service resources.** Terraform cannot make `lifecycle.ignore_changes` conditional, so `aws_ecs_service.externally_managed` and `aws_ecs_service.terraform_managed` carry identical settings and exactly one exists. Switching the variable on a live service destroys and recreates the service.

## IAM

There are two roles, both assumable only by `ecs-tasks.amazonaws.com` and only when `aws:SourceAccount` equals the current account (confused deputy protection).

### Execution role (`<name>-<environment>-execution`)

Used by ECS itself to start the task, not by your application code. Its inline policy `execution` contains these statements:

| Sid | Actions | Resources | Why |
| --- | --- | --- | --- |
| `EcrAuthorisationToken` | `ecr:GetAuthorizationToken` | `*` | AWS does not support resource-level permissions for this call; it is the only wildcard |
| `WriteServiceLogs` | `logs:CreateLogStream`, `logs:PutLogEvents` | the service log group (`:*` for its streams) | The `awslogs` driver writes one stream per container. The group is created by Terraform, so `logs:CreateLogGroup` is not granted |
| `PullImages` | `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage` | ECR repositories derived from the container image URLs, plus `extra_ecr_repository_arns` | Pull only the images of this task. Omitted when no image is in ECR |
| `ReadSecretsManagerSecrets` | `secretsmanager:GetSecretValue` | secrets named in `containers[*].secrets` and `extra_execution_secret_arns`, with any `:json-key:version-stage:version-id` suffix removed | ECS injects secrets as environment variables at start. Omitted when there are none |
| `ReadSsmParameters` | `ssm:GetParameters` | SSM parameter ARNs from the same lists | Same, for SSM parameters |
| `DecryptSecrets` | `kms:Decrypt` | `kms_key_arns` | Only needed when secrets use a customer-managed key. Omitted when the list is empty |

Use full secret ARNs including the six-character suffix, for example `arn:aws:secretsmanager:eu-west-1:123456789012:secret:example/app-AbCdEf`. A partial ARN works in the task definition but would not match the IAM resource.

### Task role (`<name>-<environment>-task`)

Used by your application. It has no permissions unless you grant them:

| Source | What it grants |
| --- | --- |
| `task_role_policy_json` (policy `application`) | Whatever policy document you pass. Scope it to specific resources |
| `enable_execute_command = true` (policy `ecs-exec`) | `ssmmessages:CreateControlChannel`, `CreateDataChannel`, `OpenControlChannel`, `OpenDataChannel` on `*`. AWS requires `*` for these. Off by default |

The only wildcard resources the module can create are `ecr:GetAuthorizationToken` and the `ssmmessages` actions above.

## Left out of the reference shape

The reference service modules also cover EC2 launch type, scheduled and ad-hoc task types, an nginx front container, a log forwarding sidecar and its endpoint settings, an observability agent sidecar, DNS records, a network load balancer, CodeDeploy blue/green with a second target group, and security group management with migration helpers. They are team and estate specific, or replaced by other modules here (security groups, ALB). The kept ideas: a service type with a placeholder image replaced by the pipeline, role arns that may be supplied or created, autoscaling profiles on CPU, and outputs for the target group suffix and family.

## Tests

`terraform test` with `mock_provider "aws"` carries over the v0.1.0 assertions: the service ignores task definition changes and desired count, the service only uses the security groups it is given, the execution role reads exactly the listed secrets, health checks use `127.0.0.1`, no wildcard IAM resource beyond the documented exceptions, a read-only root filesystem by default, and the role trust is pinned to the account. It also covers the target group, the listener rule and the validations.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 5.100.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_appautoscaling_policy.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_policy.memory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_service.externally_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_service.terraform_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task_execute_command](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_arn | ARN of the ECS cluster the service runs in | `string` | n/a | yes |
| containers | Containers of the task. secrets maps an environment variable name to a Secrets Manager or SSM parameter ARN, optionally suffixed with :json-key:: | ```list(object({ name = string image = string essential = optional(bool, true) port = optional(number) cpu = optional(number) memory = optional(number) environment = optional(map(string), {}) secrets = optional(map(string), {}) health_check = optional(object({ command = list(string) interval = optional(number, 30) timeout = optional(number, 5) retries = optional(number, 3) start_period = optional(number, 0) })) depends_on = optional(list(object({ container_name = string condition = string })), []) read_only_root_filesystem = optional(bool, true) }))``` | n/a | yes |
| cpu | Task CPU units (256, 512, 1024, ...) | `number` | n/a | yes |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| memory | Task memory in MiB | `number` | n/a | yes |
| name | Service name. Resources are named <name>-<environment> | `string` | n/a | yes |
| security\_group\_ids | Security groups attached to the tasks, for example from the security-group module. The service creates none | `list(string)` | n/a | yes |
| subnet\_ids | Subnets the tasks run in | `list(string)` | n/a | yes |
| assign\_public\_ip | Assign a public IP to tasks. Keep false unless the subnets have no NAT or endpoints | `bool` | `false` | no |
| autoscaling | Target tracking autoscaling. Set cpu\_target and/or memory\_target as utilisation percentages | ```object({ min = number max = number cpu_target = optional(number) memory_target = optional(number) })``` | `null` | no |
| capacity\_provider\_strategy | Capacity provider strategy. Empty runs the service on FARGATE | ```list(object({ capacity_provider = string weight = number base = optional(number, 0) }))``` | `[]` | no |
| cpu\_architecture | CPU architecture of the task: X86\_64 or ARM64 | `string` | `"X86_64"` | no |
| default\_health\_check\_path | When set, containers with a port and no health\_check get a curl check against http://127.0.0.1:<port><path>. The image must contain curl | `string` | `null` | no |
| deployment\_circuit\_breaker | ECS deployment circuit breaker | ```object({ enable = optional(bool, true) rollback = optional(bool, true) })``` | `{}` | no |
| desired\_count | Initial number of tasks | `number` | `1` | no |
| enable\_execute\_command | Enable ECS Exec. Adds the ssmmessages permissions to the task role | `bool` | `false` | no |
| extra\_ecr\_repository\_arns | Additional ECR repository ARNs the execution role may pull from. ECR repositories of the container images are derived automatically | `list(string)` | `[]` | no |
| extra\_execution\_secret\_arns | Additional Secrets Manager or SSM parameter ARNs the execution role may read | `list(string)` | `[]` | no |
| health\_check\_grace\_period\_seconds | Seconds ECS ignores failing load balancer health checks after a task starts. Only used with load\_balancer | `number` | `60` | no |
| kms\_key\_arns | KMS keys the execution role may decrypt (secrets encrypted with a customer-managed key) | `list(string)` | `[]` | no |
| load\_balancer | Attach the service to an existing ALB listener with a target group and a listener rule. Set at least one of host\_headers or path\_patterns. The ALB, its listener and the security group rules are owned by the alb and security-group modules | ```object({ container_name = string container_port = number vpc_id = string listener_arn = string host_headers = optional(list(string), []) path_patterns = optional(list(string), []) priority = number health_check_path = optional(string, "/") health_check_matcher = optional(string, "200") deregistration_delay = optional(number, 30) })``` | `null` | no |
| log\_kms\_key\_arn | KMS key ARN used to encrypt the service log group | `string` | `null` | no |
| log\_retention\_days | CloudWatch log retention in days | `number` | `30` | no |
| manage\_task\_definition\_externally | Ignore task\_definition and desired\_count changes on the service because deploys register new revisions outside Terraform | `bool` | `true` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| task\_role\_policy\_json | IAM policy document (JSON) attached inline to the task role | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| container\_names | Names of the containers in the task |
| execution\_role\_arn | ARN of the task execution role |
| log\_group\_name | Name of the CloudWatch log group |
| service\_arn | ARN of the ECS service |
| service\_name | Name of the ECS service |
| target\_group\_arn | ARN of the target group, null without a load balancer |
| target\_group\_arn\_suffix | ARN suffix of the target group for CloudWatch dimensions, null without a load balancer |
| task\_definition\_arn | ARN of the task definition revision Terraform last registered |
| task\_definition\_family | Task definition family. Pass it to the ecs-deploy action |
| task\_role\_arn | ARN of the task role |
| task\_role\_name | Name of the task role |
<!-- END_TF_DOCS -->