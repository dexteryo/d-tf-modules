# dex-tf-modules

Reusable Terraform modules for running services on ECS Fargate.

| Module | Purpose |
| --- | --- |
| [`modules/ecs-cluster`](modules/ecs-cluster) | Cluster with Container Insights, `FARGATE` and `FARGATE_SPOT` providers, optional ECS Exec logging |
| [`modules/ecs-service`](modules/ecs-service) | Task definition, service, security group, ALB rule, logs, least-privilege IAM roles, autoscaling |
| [`examples/ordering-agent`](examples/ordering-agent) | Cluster plus a two-container service and an encrypted DynamoDB table |

The companion repository `dex-github-actions` builds images, pushes them to ECR and deploys new task definition revisions to a service created by these modules.

## Requirements

- Terraform `>= 1.6`
- AWS provider `~> 5.0`
- For development: `tflint`, `terraform-docs`, `pre-commit`; optionally `trivy`

## How the pieces fit

1. Terraform creates the cluster and service. It owns CPU, memory, roles, secrets, ports and networking.
2. The service ignores `task_definition` and `desired_count` after creation.
3. The `ecs-service-deploy` workflow registers a new task definition revision with new image digests and updates the service.

Feed the service outputs `service_name`, `task_definition_family` and the cluster output `cluster_name` into the workflow inputs `service`, `task-definition-family` and `cluster`.

## Getting started

```
cd examples/ordering-agent
terraform init
terraform plan
```

The example uses placeholder VPC, subnet, listener and registry values. Override them with variables before a real apply.

## Development

All checks run without AWS credentials:

```
terraform fmt -check -recursive
for dir in modules/ecs-cluster modules/ecs-service examples/ordering-agent; do
  (cd "$dir" && terraform init -backend=false && terraform validate)
done
for dir in modules/ecs-cluster modules/ecs-service; do
  (cd "$dir" && terraform test)
done
tflint --init
tflint --recursive --config="$PWD/.tflint.hcl"
trivy config --ignorefile .trivyignore --skip-dirs '**/.terraform' .
```

`terraform test` uses `mock_provider "aws"`, so nothing is created and no credentials are read.

Install the hooks with `pre-commit install`; they run `terraform fmt`, `terraform validate`, `tflint` and `terraform-docs` (which fills the generated sections of each module README).

## Versioning

Tag releases `vX.Y.Z` and pin consumers with `?ref=vX.Y.Z`. See [CHANGELOG.md](CHANGELOG.md).
