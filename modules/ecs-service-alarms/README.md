# ecs-service-alarms

CloudWatch alarms for one ECS service and, optionally, the load balancer in front of it.

## Owns

- Service alarms from Container Insights and `AWS/ECS`: `cpu_utilization`, `memory_utilization`, `desired_vs_running` (metric math: desired minus running tasks), `deployment_count` and `running_tasks` (fewer than a fixed minimum).
- Load balancer alarms, only when `load_balancer` is set: `target_5xx` and `healthy_hosts`.
- Alarm names `<name>-<environment>-<alarm>`.

## Does not own

- The topic that receives notifications (`sns-topic`); pass its ARN as `alarm_actions`.
- The cluster, service and load balancer, which are given by name and ARN suffix.
- Dashboards.

## Usage

```hcl
module "alarms" {
  source = "git::ssh://git@github.com/dexteryo/d-tf-modules.git//modules/ecs-service-alarms?ref=v0.2.0"

  name          = "ordering"
  environment   = "integration"
  tags          = module.tags.all_tags
  cluster_name  = module.cluster.cluster_name
  service_name  = module.service.service_name
  alarm_actions = [module.alarm_topic.topic_arn]

  running_tasks = { enabled = true, minimum = 2 }

  load_balancer = {
    load_balancer_arn_suffix = module.alb.alb_arn_suffix
    target_group_arn_suffix  = module.service.target_group_arn_suffix
  }
}
```

## Defaults worth knowing

- Every alarm is an object with `enabled` and its own thresholds; `{ enabled = false }` switches one off.
- `running_tasks` is off by default because it needs a fixed minimum; the metric-math `desired_vs_running` alarm covers the same failure without one.
- CPU and memory alarms use the average over two five-minute periods above 80 percent.
- Container Insights must be on (the default in `ecs-cluster`) for the `ECS/ContainerInsights` alarms.

## Left out of the reference shape

The reference module takes every alarm as a string-typed object and always creates the four service alarms with a topic-less default. Here the objects are typed, each alarm can be switched off, and the load balancer alarms were added because a service behind a load balancer needs them.

## Tests

`terraform test` with `mock_provider "aws"` covers which alarms exist by default, naming, notifications on every alarm, the running task minimum, the load balancer alarms and their dimensions, switching alarms off and the metric-math expression.

## Example

`examples/basic` in this directory is a complete configuration that validates without credentials.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.6 |
| aws | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | 5.100.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_metric_alarm.cpu_utilization](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.deployment_count](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.desired_vs_running](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.healthy_hosts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.memory_utilization](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.running_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.target_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the ECS cluster, the ClusterName dimension of the Container Insights metrics | `string` | n/a | yes |
| environment | Deployment environment (for example integration, staging, production) | `string` | n/a | yes |
| name | Workload name. Alarms are named <name>-<environment>-<alarm> | `string` | n/a | yes |
| service\_name | Name of the ECS service, the ServiceName dimension of the Container Insights metrics | `string` | n/a | yes |
| alarm\_actions | ARNs notified when an alarm fires, for example the topic\_arn output of the sns-topic module | `list(string)` | `[]` | no |
| cpu\_utilization | Average CPU of the service against its reservation, in percent | ```object({ enabled = optional(bool, true) threshold = optional(number, 80) period = optional(number, 300) evaluation_periods = optional(number, 2) statistic = optional(string, "Average") })``` | `{}` | no |
| deployment\_count | Fires when more than the threshold of deployments are in progress at once | ```object({ enabled = optional(bool, true) threshold = optional(number, 1) period = optional(number, 300) evaluation_periods = optional(number, 2) })``` | `{}` | no |
| desired\_vs\_running | Fires when desired tasks minus running tasks reaches the threshold (a deployment stuck or tasks failing to start) | ```object({ enabled = optional(bool, true) threshold = optional(number, 1) period = optional(number, 60) evaluation_periods = optional(number, 3) })``` | `{}` | no |
| healthy\_hosts | Fires when the target group has fewer than minimum healthy targets. Needs load\_balancer | ```object({ enabled = optional(bool, true) minimum = optional(number, 1) period = optional(number, 60) evaluation_periods = optional(number, 2) })``` | `{}` | no |
| load\_balancer | Dimensions of the load balancer and target group in front of the service. The target\_5xx and healthy\_hosts alarms exist only when this is set | ```object({ load_balancer_arn_suffix = string target_group_arn_suffix = string })``` | `null` | no |
| memory\_utilization | Average memory of the service against its reservation, in percent | ```object({ enabled = optional(bool, true) threshold = optional(number, 80) period = optional(number, 300) evaluation_periods = optional(number, 2) statistic = optional(string, "Average") })``` | `{}` | no |
| ok\_actions | ARNs notified when an alarm returns to OK | `list(string)` | `[]` | no |
| running\_tasks | Fires when fewer than minimum tasks are running. Off by default because it needs a fixed minimum | ```object({ enabled = optional(bool, false) minimum = optional(number, 1) period = optional(number, 60) evaluation_periods = optional(number, 3) })``` | `{}` | no |
| tags | Tags for every resource, usually the all\_tags output of the tags module | `map(string)` | `{}` | no |
| target\_5xx | Fires when the targets answer more than threshold server errors in one period. Needs load\_balancer | ```object({ enabled = optional(bool, true) threshold = optional(number, 5) period = optional(number, 300) evaluation_periods = optional(number, 1) })``` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alarm\_arns | ARN of every alarm that exists, keyed by alarm: cpu\_utilization, memory\_utilization, desired\_vs\_running, deployment\_count, running\_tasks, target\_5xx, healthy\_hosts |
| alarms | Name, metric, threshold and notification targets of every alarm that exists, keyed like alarm\_arns |
<!-- END_TF_DOCS -->