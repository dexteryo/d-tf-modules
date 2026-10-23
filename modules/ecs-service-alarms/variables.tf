variable "name" {
  description = "Workload name. Alarms are named <name>-<environment>-<alarm>"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the ECS cluster, the ClusterName dimension of the Container Insights metrics"
  type        = string
}

variable "service_name" {
  description = "Name of the ECS service, the ServiceName dimension of the Container Insights metrics"
  type        = string
}

variable "alarm_actions" {
  description = "ARNs notified when an alarm fires, for example the topic_arn output of the sns-topic module"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs notified when an alarm returns to OK"
  type        = list(string)
  default     = []
}

variable "load_balancer" {
  description = "Dimensions of the load balancer and target group in front of the service. The target_5xx and healthy_hosts alarms exist only when this is set"
  type = object({
    load_balancer_arn_suffix = string
    target_group_arn_suffix  = string
  })
  default = null
}

variable "cpu_utilization" {
  description = "Average CPU of the service against its reservation, in percent"
  type = object({
    enabled            = optional(bool, true)
    threshold          = optional(number, 80)
    period             = optional(number, 300)
    evaluation_periods = optional(number, 2)
    statistic          = optional(string, "Average")
  })
  default = {}
}

variable "memory_utilization" {
  description = "Average memory of the service against its reservation, in percent"
  type = object({
    enabled            = optional(bool, true)
    threshold          = optional(number, 80)
    period             = optional(number, 300)
    evaluation_periods = optional(number, 2)
    statistic          = optional(string, "Average")
  })
  default = {}
}

variable "desired_vs_running" {
  description = "Fires when desired tasks minus running tasks reaches the threshold (a deployment stuck or tasks failing to start)"
  type = object({
    enabled            = optional(bool, true)
    threshold          = optional(number, 1)
    period             = optional(number, 60)
    evaluation_periods = optional(number, 3)
  })
  default = {}
}

variable "deployment_count" {
  description = "Fires when more than the threshold of deployments are in progress at once"
  type = object({
    enabled            = optional(bool, true)
    threshold          = optional(number, 1)
    period             = optional(number, 300)
    evaluation_periods = optional(number, 2)
  })
  default = {}
}

variable "running_tasks" {
  description = "Fires when fewer than minimum tasks are running. Off by default because it needs a fixed minimum"
  type = object({
    enabled            = optional(bool, false)
    minimum            = optional(number, 1)
    period             = optional(number, 60)
    evaluation_periods = optional(number, 3)
  })
  default = {}
}

variable "target_5xx" {
  description = "Fires when the targets answer more than threshold server errors in one period. Needs load_balancer"
  type = object({
    enabled            = optional(bool, true)
    threshold          = optional(number, 5)
    period             = optional(number, 300)
    evaluation_periods = optional(number, 1)
  })
  default = {}
}

variable "healthy_hosts" {
  description = "Fires when the target group has fewer than minimum healthy targets. Needs load_balancer"
  type = object({
    enabled            = optional(bool, true)
    minimum            = optional(number, 1)
    period             = optional(number, 60)
    evaluation_periods = optional(number, 2)
  })
  default = {}
}
