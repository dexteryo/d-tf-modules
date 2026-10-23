locals {
  full_name = "${var.name}-${var.environment}"

  service_dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }

  load_balancer_dimensions = var.load_balancer == null ? {} : {
    LoadBalancer = var.load_balancer.load_balancer_arn_suffix
    TargetGroup  = var.load_balancer.target_group_arn_suffix
  }

  alarm_tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = var.cpu_utilization.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-cpu-high"
  alarm_description   = "CPU of ${var.service_name} is above ${var.cpu_utilization.threshold} percent of its reservation"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.service_dimensions
  statistic           = var.cpu_utilization.statistic
  period              = var.cpu_utilization.period
  evaluation_periods  = var.cpu_utilization.evaluation_periods
  threshold           = var.cpu_utilization.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags
}

resource "aws_cloudwatch_metric_alarm" "memory_utilization" {
  count = var.memory_utilization.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-memory-high"
  alarm_description   = "Memory of ${var.service_name} is above ${var.memory_utilization.threshold} percent of its reservation"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.service_dimensions
  statistic           = var.memory_utilization.statistic
  period              = var.memory_utilization.period
  evaluation_periods  = var.memory_utilization.evaluation_periods
  threshold           = var.memory_utilization.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags
}

resource "aws_cloudwatch_metric_alarm" "desired_vs_running" {
  count = var.desired_vs_running.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-desired-vs-running"
  alarm_description   = "${var.service_name} has ${var.desired_vs_running.threshold} or more tasks fewer running than desired"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.desired_vs_running.evaluation_periods
  threshold           = var.desired_vs_running.threshold
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags

  metric_query {
    id          = "gap"
    expression  = "desired - running"
    label       = "Desired minus running tasks"
    return_data = true
  }

  metric_query {
    id = "desired"

    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "DesiredTaskCount"
      dimensions  = local.service_dimensions
      period      = var.desired_vs_running.period
      stat        = "Minimum"
    }
  }

  metric_query {
    id = "running"

    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "RunningTaskCount"
      dimensions  = local.service_dimensions
      period      = var.desired_vs_running.period
      stat        = "Minimum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "deployment_count" {
  count = var.deployment_count.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-deployment-count"
  alarm_description   = "More than ${var.deployment_count.threshold} deployments of ${var.service_name} are in progress"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "DeploymentCount"
  dimensions          = local.service_dimensions
  statistic           = "Maximum"
  period              = var.deployment_count.period
  evaluation_periods  = var.deployment_count.evaluation_periods
  threshold           = var.deployment_count.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags
}

resource "aws_cloudwatch_metric_alarm" "running_tasks" {
  count = var.running_tasks.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-running-tasks-below-minimum"
  alarm_description   = "Fewer than ${var.running_tasks.minimum} tasks of ${var.service_name} are running"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = local.service_dimensions
  statistic           = "Minimum"
  period              = var.running_tasks.period
  evaluation_periods  = var.running_tasks.evaluation_periods
  threshold           = var.running_tasks.minimum
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count = var.load_balancer != null && var.target_5xx.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-target-5xx"
  alarm_description   = "The targets of ${var.service_name} answered more than ${var.target_5xx.threshold} server errors in ${var.target_5xx.period} seconds"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.load_balancer_dimensions
  statistic           = "Sum"
  period              = var.target_5xx.period
  evaluation_periods  = var.target_5xx.evaluation_periods
  threshold           = var.target_5xx.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts" {
  count = var.load_balancer != null && var.healthy_hosts.enabled ? 1 : 0

  alarm_name          = "${local.full_name}-no-healthy-host"
  alarm_description   = "Fewer than ${var.healthy_hosts.minimum} healthy targets of ${var.service_name} are behind the load balancer"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.load_balancer_dimensions
  statistic           = "Minimum"
  period              = var.healthy_hosts.period
  evaluation_periods  = var.healthy_hosts.evaluation_periods
  threshold           = var.healthy_hosts.minimum
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = local.alarm_tags
}
