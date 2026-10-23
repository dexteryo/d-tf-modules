mock_provider "aws" {
  mock_data "aws_ec2_managed_prefix_list" {
    defaults = {
      id = "pl-0123456789abcdef0"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/mock/0123456789abcdef"
      arn_suffix = "app/mock/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/mock/0123456789abcdef/0123456789abcdef"
    }
  }
}

variables {
  name        = "ordering"
  environment = "integration"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  tags        = { Environment = "integration" }

  listeners = {
    public = {
      port            = 443
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    }
  }
}

run "secure_defaults" {
  command = apply

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields && aws_lb.this.enable_deletion_protection
    error_message = "Invalid headers must be dropped and deletion protection must be on by default."
  }

  assert {
    condition     = aws_lb.this.internal == false && aws_lb.this.load_balancer_type == "application"
    error_message = "The module creates an internet-facing application load balancer by default."
  }

  assert {
    condition     = aws_lb.this.name == "ordering-integration"
    error_message = "The load balancer is named <name>-<environment>."
  }

  assert {
    condition     = output.load_balancer.drop_invalid_header_fields && output.load_balancer.deletion_protection && output.load_balancer.internal == false && output.load_balancer.access_logs_enabled == false
    error_message = "The load balancer output must describe the secure defaults."
  }
}

run "no_ingress_unless_asked_for" {
  command = apply

  assert {
    condition     = length(output.ingress_rules) == 0 && length(output.egress_rules) == 0
    error_message = "Without ingress options and egress rules the security group is closed."
  }
}

run "cloudfront_only_accepts_https_from_the_prefix_list_and_nothing_else" {
  command = apply

  variables {
    cloudfront_only = true
  }

  assert {
    condition     = output.ingress_rules["cloudfront"].prefix_list_id == "pl-0123456789abcdef0"
    error_message = "The ingress must name the CloudFront origin-facing prefix list."
  }

  assert {
    condition     = output.ingress_rules["cloudfront"].from_port == 443 && output.ingress_rules["cloudfront"].to_port == 443
    error_message = "The ingress is HTTPS only."
  }

  assert {
    condition     = output.ingress_rules["cloudfront"].cidr_ipv4 == null && output.ingress_rules["cloudfront"].cidr_ipv6 == null && output.ingress_rules["cloudfront"].referenced_security_group_id == null
    error_message = "The ingress has no CIDR or security group source."
  }

  assert {
    condition     = length(output.ingress_rules) == 1
    error_message = "CloudFront-only must not add other sources."
  }
}

run "cidr_and_prefix_list_ingress_use_the_ingress_port" {
  command = apply

  variables {
    ingress_port            = 8443
    ingress_cidrs           = ["10.0.0.0/16"]
    ingress_prefix_list_ids = ["pl-0fedcba9876543210"]
  }

  assert {
    condition     = output.ingress_rules["cidr-10-0-0-0-16"].from_port == 8443 && output.ingress_rules["prefix-list-pl-0fedcba9876543210"].to_port == 8443
    error_message = "Every ingress option uses ingress_port."
  }
}

run "egress_goes_only_where_it_is_listed" {
  command = apply

  variables {
    egress_rules = {
      to-tasks = {
        description                  = "Agent port of the service"
        from_port                    = 8788
        to_port                      = 8788
        referenced_security_group_id = "sg-0fedcba9876543210"
      }
    }
  }

  assert {
    condition     = output.egress_rules["to-tasks"].referenced_security_group_id == "sg-0fedcba9876543210" && output.egress_rules["to-tasks"].from_port == 8788
    error_message = "The egress rule must reference the service security group and its port."
  }
}

run "listener_answers_403_without_a_default_target_group" {
  command = apply

  assert {
    condition     = aws_lb_listener.this["public"].default_action[0].type == "fixed-response" && aws_lb_listener.this["public"].default_action[0].fixed_response[0].status_code == "403"
    error_message = "The default action of a listener must be a 403."
  }

  assert {
    condition     = aws_lb_listener.this["public"].protocol == "HTTPS" && aws_lb_listener.this["public"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "Listeners are HTTPS with a TLS 1.2 or later policy."
  }

  assert {
    condition     = output.listeners["public"].default_action_type == "fixed-response" && output.listeners["public"].default_status_code == "403" && output.listeners["public"].port == 443
    error_message = "The listeners output must describe the closed default action."
  }
}

run "listener_with_a_default_target_group_forwards" {
  command = apply

  variables {
    listeners = {
      public = {
        port                     = 443
        certificate_arn          = "arn:aws:acm:eu-west-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
        default_target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/mock/0123456789abcdef"
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["public"].default_action[0].type == "forward"
    error_message = "A default target group must be forwarded to."
  }
}

run "header_rule_forwards_only_requests_with_the_secret_header" {
  command = apply

  variables {
    header_forward_rules = {
      from-edge = {
        listener         = "public"
        priority         = 10
        header_name      = "X-Origin-Verify"
        target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/mock/0123456789abcdef"
      }
    }
    header_values = { from-edge = "origin-header-value-for-tests" }
  }

  assert {
    condition     = one([for c in aws_lb_listener_rule.header_forward["from-edge"].condition : one([for h in c.http_header : h.http_header_name])]) == "X-Origin-Verify"
    error_message = "The rule must match the header name."
  }

  assert {
    condition     = one([for c in aws_lb_listener_rule.header_forward["from-edge"].condition : one([for h in c.http_header : one(h.values)])]) == "origin-header-value-for-tests"
    error_message = "The rule must match the header value."
  }

  assert {
    condition     = aws_lb_listener_rule.header_forward["from-edge"].action[0].type == "forward"
    error_message = "A matching request is forwarded."
  }

  assert {
    condition     = output.header_forward_rules["from-edge"].header_name == "X-Origin-Verify" && output.header_forward_rules["from-edge"].header_value == "origin-header-value-for-tests"
    error_message = "The header_forward_rules output must describe the match."
  }
}

run "header_rule_for_an_unknown_listener_is_refused" {
  command = plan

  variables {
    header_forward_rules = {
      broken = {
        listener         = "missing"
        priority         = 10
        header_name      = "X-Origin-Verify"
        target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/mock/0123456789abcdef"
      }
    }
    header_values = { broken = "x" }
  }

  expect_failures = [aws_lb_listener_rule.header_forward]
}

run "access_logs_are_enabled_when_a_bucket_is_given" {
  command = apply

  variables {
    access_logs = { bucket = "example-alb-logs", prefix = "ordering" }
  }

  assert {
    condition     = aws_lb.this.access_logs[0].enabled && aws_lb.this.access_logs[0].bucket == "example-alb-logs"
    error_message = "Access logs must go to the given bucket."
  }

  assert {
    condition     = output.load_balancer.access_logs_enabled && output.load_balancer.access_logs_bucket == "example-alb-logs"
    error_message = "The load balancer output must describe the access logs."
  }
}

run "idle_timeout_is_configurable" {
  command = apply

  variables {
    idle_timeout = 120
  }

  assert {
    condition     = aws_lb.this.idle_timeout == 120
    error_message = "idle_timeout must reach the load balancer."
  }
}

run "name_longer_than_32_characters_is_refused" {
  command = plan

  variables {
    name = "an-unreasonably-long-workload-name"
  }

  expect_failures = [aws_lb.this]
}

run "needs_two_subnets" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}
