locals {
  alarms = merge(
    { for alarm in aws_cloudwatch_metric_alarm.cpu_utilization : "cpu_utilization" => alarm },
    { for alarm in aws_cloudwatch_metric_alarm.memory_utilization : "memory_utilization" => alarm },
    { for alarm in aws_cloudwatch_metric_alarm.desired_vs_running : "desired_vs_running" => alarm },
    { for alarm in aws_cloudwatch_metric_alarm.deployment_count : "deployment_count" => alarm },
    { for alarm in aws_cloudwatch_metric_alarm.running_tasks : "running_tasks" => alarm },
    { for alarm in aws_cloudwatch_metric_alarm.target_5xx : "target_5xx" => alarm },
    { for alarm in aws_cloudwatch_metric_alarm.healthy_hosts : "healthy_hosts" => alarm },
  )
}

output "alarm_arns" {
  description = "ARN of every alarm that exists, keyed by alarm: cpu_utilization, memory_utilization, desired_vs_running, deployment_count, running_tasks, target_5xx, healthy_hosts"
  value       = { for key, alarm in local.alarms : key => alarm.arn }
}

output "alarms" {
  description = "Name, metric, threshold and notification targets of every alarm that exists, keyed like alarm_arns"
  value = {
    for key, alarm in local.alarms : key => {
      alarm_name          = alarm.alarm_name
      namespace           = alarm.namespace
      metric_name         = alarm.metric_name
      statistic           = alarm.statistic
      period              = alarm.period
      threshold           = alarm.threshold
      comparison_operator = alarm.comparison_operator
      alarm_actions       = alarm.alarm_actions
    }
  }
}
