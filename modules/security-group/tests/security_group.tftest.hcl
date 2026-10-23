mock_provider "aws" {}

variables {
  name        = "ordering"
  environment = "integration"
  vpc_id      = "vpc-0123456789abcdef0"
  tags        = { Environment = "integration" }
}

run "no_rules_and_no_outbound_traffic_by_default" {
  command = apply

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 0 && length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "A security group without rules must not open anything."
  }

  assert {
    condition     = length(aws_security_group.this.ingress) == 0 && length(aws_security_group.this.egress) == 0
    error_message = "No inline rules are allowed."
  }
}

run "name_is_built_from_the_inputs" {
  command = apply

  variables {
    name_suffix = "tasks"
  }

  assert {
    condition     = aws_security_group.this.name_prefix == "ordering-integration-tasks-" && aws_security_group.this.tags["Name"] == "ordering-integration-tasks"
    error_message = "The name must be <name>-<environment>-<name_suffix>."
  }

  assert {
    condition     = aws_security_group.this.description == "Security group of ordering-integration-tasks"
    error_message = "The default description must be built from the name."
  }
}

run "ingress_only_from_the_load_balancer_security_group" {
  command = apply

  variables {
    ingress_rules = {
      from-alb = {
        description                  = "Application port from the load balancer"
        from_port                    = 8788
        to_port                      = 8788
        referenced_security_group_id = "sg-0123456789abcdef0"
      }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "Exactly one ingress rule is expected."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from-alb"].referenced_security_group_id == "sg-0123456789abcdef0"
    error_message = "Ingress must reference the load balancer security group."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from-alb"].cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.this["from-alb"].cidr_ipv6 == null && aws_vpc_security_group_ingress_rule.this["from-alb"].prefix_list_id == null
    error_message = "Ingress must not use CIDR ranges or prefix lists."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from-alb"].from_port == 8788 && aws_vpc_security_group_ingress_rule.this["from-alb"].to_port == 8788 && aws_vpc_security_group_ingress_rule.this["from-alb"].ip_protocol == "tcp"
    error_message = "Ingress must be limited to the container port over TCP."
  }
}

run "prefix_list_ingress_has_no_other_source" {
  command = apply

  variables {
    ingress_rules = {
      https-from-edge = {
        description    = "HTTPS from an edge prefix list"
        from_port      = 443
        to_port        = 443
        prefix_list_id = "pl-0123456789abcdef0"
      }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["https-from-edge"].prefix_list_id == "pl-0123456789abcdef0" && aws_vpc_security_group_ingress_rule.this["https-from-edge"].cidr_ipv4 == null
    error_message = "A prefix list rule must have the prefix list as its only source."
  }
}

run "egress_rules_are_created_as_listed" {
  command = apply

  variables {
    egress_rules = {
      https = {
        description = "HTTPS to AWS APIs"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "10.0.0.0/16"
      }
      everything-to-peer = {
        description                  = "All traffic to a peer group"
        protocol                     = "-1"
        referenced_security_group_id = "sg-0fedcba9876543210"
      }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 2
    error_message = "Every listed egress rule must exist."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["everything-to-peer"].ip_protocol == "-1" && aws_vpc_security_group_egress_rule.this["everything-to-peer"].from_port == null
    error_message = "Protocol -1 must carry no ports."
  }
}

run "rule_with_two_sources_is_refused" {
  command = plan

  variables {
    ingress_rules = {
      both = {
        description                  = "Two sources"
        from_port                    = 80
        to_port                      = 80
        cidr_ipv4                    = "10.0.0.0/16"
        referenced_security_group_id = "sg-0123456789abcdef0"
      }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rule_without_ports_is_refused_unless_protocol_is_all" {
  command = plan

  variables {
    egress_rules = {
      no-ports = {
        description = "Missing ports"
        cidr_ipv4   = "10.0.0.0/16"
      }
    }
  }

  expect_failures = [var.egress_rules]
}
