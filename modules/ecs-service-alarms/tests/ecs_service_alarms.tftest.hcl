mock_provider "aws" {}

variables {
  name         = "ordering"
  environment  = "integration"
  tags         = { Environment = "integration" }
  cluster_name = "ordering-integration"
  service_name = "ordering-integration"
  alarm_actions = [
    "arn:aws:sns:eu-west-1:123456789012:ordering-alarms",
  ]
}

run "service_alarms_exist_by_default_and_the_load_balancer_ones_do_not" {
  command = apply

  assert {
    condition     = toset(keys(output.alarm_arns)) == toset(["cpu_utilization", "memory_utilization", "desired_vs_running", "deployment_count"])
    error_message = "Without a load balancer only the four service alarms exist."
  }
}

run "alarm_names_are_built_from_the_inputs" {
  command = apply

  assert {
    condition     = output.alarms["cpu_utilization"].alarm_name == "ordering-integration-cpu-high" && output.alarms["deployment_count"].alarm_name == "ordering-integration-deployment-count"
    error_message = "Alarms are named <name>-<environment>-<alarm>."
  }
}

run "every_alarm_notifies_the_given_topic" {
  command = apply

  variables {
    running_tasks = { enabled = true, minimum = 2 }
    load_balancer = {
      load_balancer_arn_suffix = "app/mock/0123456789abcdef"
      target_group_arn_suffix  = "targetgroup/mock/0123456789abcdef"
    }
  }

  assert {
    condition = alltrue([
      for alarm in values(output.alarms) : toset(alarm.alarm_actions) == toset(["arn:aws:sns:eu-west-1:123456789012:ordering-alarms"])
    ])
    error_message = "Every alarm must notify the topic from alarm_actions."
  }

  assert {
    condition     = length(output.alarms) == 7
    error_message = "All seven alarms exist when everything is enabled."
  }
}

run "running_tasks_alarm_fires_below_the_minimum" {
  command = apply

  variables {
    running_tasks = { enabled = true, minimum = 2 }
  }

  assert {
    condition     = output.alarms["running_tasks"].metric_name == "RunningTaskCount" && output.alarms["running_tasks"].namespace == "ECS/ContainerInsights" && output.alarms["running_tasks"].threshold == 2 && output.alarms["running_tasks"].comparison_operator == "LessThanThreshold"
    error_message = "Running tasks below the minimum must alarm."
  }
}

run "load_balancer_alarms_watch_errors_and_healthy_targets" {
  command = apply

  variables {
    load_balancer = {
      load_balancer_arn_suffix = "app/mock/0123456789abcdef"
      target_group_arn_suffix  = "targetgroup/mock/0123456789abcdef"
    }
  }

  assert {
    condition     = output.alarms["target_5xx"].metric_name == "HTTPCode_Target_5XX_Count" && output.alarms["target_5xx"].threshold == 5 && output.alarms["target_5xx"].period == 300 && output.alarms["target_5xx"].statistic == "Sum" && output.alarms["target_5xx"].comparison_operator == "GreaterThanThreshold"
    error_message = "More than 5 target 5xx in 5 minutes must alarm."
  }

  assert {
    condition     = output.alarms["healthy_hosts"].metric_name == "HealthyHostCount" && output.alarms["healthy_hosts"].threshold == 1 && output.alarms["healthy_hosts"].comparison_operator == "LessThanThreshold"
    error_message = "Fewer than one healthy host must alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.healthy_hosts[0].dimensions["TargetGroup"] == "targetgroup/mock/0123456789abcdef" && aws_cloudwatch_metric_alarm.healthy_hosts[0].dimensions["LoadBalancer"] == "app/mock/0123456789abcdef"
    error_message = "The load balancer alarms need both dimensions."
  }
}

run "each_alarm_can_be_switched_off" {
  command = apply

  variables {
    cpu_utilization    = { enabled = false }
    memory_utilization = { enabled = false }
    desired_vs_running = { enabled = false }
    deployment_count   = { enabled = false }
  }

  assert {
    condition     = length(output.alarms) == 0
    error_message = "Disabled alarms must not be created."
  }
}

run "desired_vs_running_uses_a_metric_math_gap" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.desired_vs_running[0].metric_query) == 3 && one([for q in aws_cloudwatch_metric_alarm.desired_vs_running[0].metric_query : q.expression if q.id == "gap"]) == "desired - running"
    error_message = "The alarm compares desired and running task counts."
  }
}
