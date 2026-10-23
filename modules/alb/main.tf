data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = var.cloudfront_only ? 1 : 0

  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  full_name = "${var.name}-${var.environment}"

  ingress_rules = merge(
    var.cloudfront_only ? {
      cloudfront = {
        description    = "Traffic from the CloudFront origin-facing prefix list"
        from_port      = var.ingress_port
        to_port        = var.ingress_port
        prefix_list_id = one(data.aws_ec2_managed_prefix_list.cloudfront[*].id)
      }
    } : {},
    {
      for cidr in var.ingress_cidrs : "cidr-${replace(replace(cidr, ".", "-"), "/", "-")}" => {
        description = "Traffic from ${cidr}"
        from_port   = var.ingress_port
        to_port     = var.ingress_port
        cidr_ipv4   = cidr
      }
    },
    {
      for id in var.ingress_prefix_list_ids : "prefix-list-${id}" => {
        description    = "Traffic from the prefix list ${id}"
        from_port      = var.ingress_port
        to_port        = var.ingress_port
        prefix_list_id = id
      }
    },
  )
}

module "security_group" {
  source = "../security-group"

  name        = var.name
  environment = var.environment
  name_suffix = "alb"
  description = "Load balancer ${local.full_name}"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress_rules = local.ingress_rules
  egress_rules  = var.egress_rules
}

resource "aws_lb" "this" {
  name                       = local.full_name
  load_balancer_type         = "application"
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = [module.security_group.security_group_id]
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = var.drop_invalid_header_fields
  enable_deletion_protection = var.enable_deletion_protection
  tags                       = merge(var.tags, { Name = local.full_name })

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : [var.access_logs]

    content {
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
      enabled = true
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.full_name) <= 32
      error_message = "The load balancer name <name>-<environment> must be at most 32 characters."
    }
  }
}

resource "aws_lb_listener" "this" {
  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = "HTTPS"
  ssl_policy        = each.value.ssl_policy
  certificate_arn   = each.value.certificate_arn
  tags              = var.tags

  dynamic "default_action" {
    for_each = each.value.default_target_group_arn == null ? [] : [each.value.default_target_group_arn]

    content {
      type             = "forward"
      target_group_arn = default_action.value
    }
  }

  dynamic "default_action" {
    for_each = each.value.default_target_group_arn == null ? [1] : []

    content {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
    }
  }
}

resource "aws_lb_listener_rule" "header_forward" {
  for_each = var.header_forward_rules

  listener_arn = try(aws_lb_listener.this[each.value.listener].arn, null)
  priority     = each.value.priority
  tags         = var.tags

  lifecycle {
    precondition {
      condition     = contains(keys(var.listeners), each.value.listener)
      error_message = "The header_forward_rules entry ${each.key} must name a listener from listeners."
    }
  }

  action {
    type             = "forward"
    target_group_arn = each.value.target_group_arn
  }

  condition {
    http_header {
      http_header_name = each.value.header_name
      values           = [var.header_values[each.key]]
    }
  }
}
