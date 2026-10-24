mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/ordering-integration/vpc-flow"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/ordering-integration-vpc-flow"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  name               = "ordering"
  environment        = "integration"
  cidr_block         = "10.20.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  logs_kms_key_arn   = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  tags               = { Environment = "integration" }
}

run "vpc_is_named_tagged_and_resolves_dns" {
  command = apply

  assert {
    condition     = aws_vpc.this.tags["Name"] == "ordering-integration" && aws_vpc.this.tags["Environment"] == "integration"
    error_message = "The VPC must be named from name and environment and carry the tags input."
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "DNS support and hostnames are needed for private endpoints."
  }
}

run "each_tier_has_one_subnet_per_zone_with_fixed_cidrs" {
  command = apply

  assert {
    condition     = [for s in aws_subnet.public : s.cidr_block] == ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    error_message = "Public subnets are /24s starting at the first block."
  }

  assert {
    condition     = [for s in aws_subnet.private : s.cidr_block] == ["10.20.16.0/22", "10.20.20.0/22", "10.20.24.0/22"]
    error_message = "Private subnets are /22s starting at 10.20.16.0."
  }

  assert {
    condition     = [for s in aws_subnet.isolated : s.cidr_block] == ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
    error_message = "Isolated subnets are /24s starting at 10.20.10.0."
  }

  assert {
    condition     = tolist([for s in aws_subnet.private : s.availability_zone]) == var.availability_zones && tolist([for s in aws_subnet.isolated : s.availability_zone]) == var.availability_zones
    error_message = "Subnets must follow the order of availability_zones."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : !s.map_public_ip_on_launch]) && aws_subnet.private[0].tags["Tier"] == "private"
    error_message = "Nothing gets a public IP on launch, and subnets carry a Tier tag."
  }
}

run "every_zone_has_its_own_nat_gateway_and_private_route" {
  command = apply

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_eip.nat) == 3 && length(aws_route.private_nat) == 3
    error_message = "One NAT gateway, address and private route per zone."
  }

  assert {
    condition     = alltrue([for route in aws_route.private_nat : route.destination_cidr_block == "0.0.0.0/0"])
    error_message = "Private subnets send all other traffic to the NAT gateway."
  }

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public subnets route to the internet gateway."
  }
}

run "default_security_group_admits_nothing" {
  command = apply

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "The default security group must have no rules."
  }
}

run "s3_gateway_endpoint_is_on_by_default_and_skips_public_subnets" {
  command = apply

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 1 && aws_vpc_endpoint.gateway["s3"].service_name == "com.amazonaws.eu-west-1.s3"
    error_message = "An S3 gateway endpoint exists by default."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway["s3"].route_table_ids) == 4
    error_message = "It attaches to the three private route tables and the isolated one."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "No interface endpoint unless asked for."
  }
}

run "interface_endpoints_sit_in_private_subnets_behind_the_vpc_only_group" {
  command = apply

  variables {
    interface_endpoint_services = ["logs", "ecr.api"]
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 2 && aws_vpc_endpoint.interface["logs"].service_name == "com.amazonaws.eu-west-1.logs" && aws_vpc_endpoint.interface["logs"].private_dns_enabled
    error_message = "Each requested service gets an endpoint with private DNS."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_https.cidr_ipv4 == "10.20.0.0/16" && aws_vpc_security_group_ingress_rule.endpoints_https.from_port == 443
    error_message = "The endpoint group admits HTTPS from the VPC only."
  }
}

run "flow_logs_capture_all_traffic_into_an_encrypted_group" {
  command = apply

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL" && aws_flow_log.this.log_destination_type == "cloud-watch-logs"
    error_message = "Flow logs must capture accepted and rejected traffic into CloudWatch Logs."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow.kms_key_id == var.logs_kms_key_arn && aws_cloudwatch_log_group.flow.retention_in_days == 365 && aws_cloudwatch_log_group.flow.name == "/ordering-integration/vpc-flow"
    error_message = "The log group is encrypted with the given key, named from the inputs and kept for a year."
  }
}

run "other_zone_counts_scale_the_layout" {
  command = apply

  variables {
    availability_zones = ["eu-west-1a", "eu-west-1b"]
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_nat_gateway.this) == 2 && length(aws_route_table.private) == 2
    error_message = "Two zones give two of everything per zone."
  }
}

run "one_zone_is_rejected" {
  command = plan

  variables {
    availability_zones = ["eu-west-1a"]
  }

  expect_failures = [var.availability_zones]
}

run "cidr_other_than_slash_16_is_rejected" {
  command = plan

  variables {
    cidr_block = "10.20.0.0/20"
  }

  expect_failures = [var.cidr_block]
}

run "unknown_gateway_service_is_rejected" {
  command = plan

  variables {
    gateway_endpoint_services = ["sqs"]
  }

  expect_failures = [var.gateway_endpoint_services]
}
