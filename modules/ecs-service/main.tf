resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.full_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn
  tags              = local.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode(local.container_definitions)

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.load_balancer == null || contains(var.containers[*].name, var.load_balancer.container_name)
      error_message = "load_balancer.container_name must match one of the containers."
    }
  }
}

resource "aws_security_group" "this" {
  name        = local.full_name
  description = "Tasks of ${local.full_name}"
  vpc_id      = var.vpc_id
  tags        = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  count = local.load_balancer_enabled ? 1 : 0

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.load_balancer.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.load_balancer.container_port
  to_port                      = var.load_balancer.container_port
  description                  = "Application port from the load balancer"
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound to ECR, Secrets Manager, AWS APIs and dependencies"
  tags              = local.tags
}

resource "aws_lb_target_group" "this" {
  count = local.load_balancer_enabled ? 1 : 0

  name_prefix          = substr(var.name, 0, 6)
  vpc_id               = var.vpc_id
  port                 = var.load_balancer.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  deregistration_delay = var.load_balancer.deregistration_delay

  health_check {
    path    = var.load_balancer.health_check_path
    matcher = var.load_balancer.health_check_matcher
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "this" {
  count = local.load_balancer_enabled ? 1 : 0

  listener_arn = var.load_balancer.listener_arn
  priority     = var.load_balancer.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.host_headers) > 0 ? [1] : []

    content {
      host_header {
        values = var.load_balancer.host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.path_patterns) > 0 ? [1] : []

    content {
      path_pattern {
        values = var.load_balancer.path_patterns
      }
    }
  }

  tags = local.tags
}

resource "aws_ecs_service" "externally_managed" {
  count = var.manage_task_definition_externally ? 1 : 0

  name                              = local.full_name
  cluster                           = var.cluster_arn
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  launch_type                       = length(var.capacity_provider_strategy) == 0 ? "FARGATE" : null
  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = local.load_balancer_enabled ? var.health_check_grace_period_seconds : null
  propagate_tags                    = "SERVICE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = var.assign_public_ip
  }

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker.enable
    rollback = var.deployment_circuit_breaker.rollback
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "load_balancer" {
    for_each = local.load_balancer_enabled ? [var.load_balancer] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  tags = local.tags

  depends_on = [aws_lb_listener_rule.this]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_ecs_service" "terraform_managed" {
  count = var.manage_task_definition_externally ? 0 : 1

  name                              = local.full_name
  cluster                           = var.cluster_arn
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  launch_type                       = length(var.capacity_provider_strategy) == 0 ? "FARGATE" : null
  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = local.load_balancer_enabled ? var.health_check_grace_period_seconds : null
  propagate_tags                    = "SERVICE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = var.assign_public_ip
  }

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker.enable
    rollback = var.deployment_circuit_breaker.rollback
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "load_balancer" {
    for_each = local.load_balancer_enabled ? [var.load_balancer] : []

    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  tags = local.tags

  depends_on = [aws_lb_listener_rule.this]
}

resource "aws_appautoscaling_target" "this" {
  count = var.autoscaling != null ? 1 : 0

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${local.cluster_name}/${local.full_name}"
  min_capacity       = var.autoscaling.min
  max_capacity       = var.autoscaling.max
  tags               = local.tags

  depends_on = [aws_ecs_service.externally_managed, aws_ecs_service.terraform_managed]
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.autoscaling != null && try(var.autoscaling.cpu_target, null) != null ? 1 : 0

  name               = "${local.full_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscaling.cpu_target

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.autoscaling != null && try(var.autoscaling.memory_target, null) != null ? 1 : 0

  name               = "${local.full_name}-memory"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscaling.memory_target

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
