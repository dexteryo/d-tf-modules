mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  mock_resource "aws_instance" {
    defaults = {
      id = "i-0123456789abcdef0"
    }
  }
}

variables {
  name              = "ordering"
  environment       = "integration"
  tags              = { Environment = "integration" }
  vpc_id            = "vpc-0123456789abcdef0"
  subnet_id         = "subnet-0123456789abcdef0"
  egress_ipv4_cidrs = ["203.0.113.0/24", "198.51.100.0/24"]
  kms_key_arn       = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}

run "instance_is_private_hardened_and_named_from_the_inputs" {
  command = apply

  assert {
    condition     = aws_instance.this.tags["Name"] == "ordering-integration-egress-proxy" && aws_iam_role.this.name == "ordering-integration-egress-proxy"
    error_message = "Resources are named <name>-<environment>-<name_suffix>."
  }

  assert {
    condition     = aws_instance.this.tags["Environment"] == "integration"
    error_message = "Tags must be applied."
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false && aws_instance.this.subnet_id == var.subnet_id
    error_message = "The instance must sit in the given subnet without a public IP."
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Instance metadata must require IMDSv2 with a hop limit of 1."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted && aws_instance.this.root_block_device[0].kms_key_id == var.kms_key_arn
    error_message = "The root volume must be encrypted with the given key."
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0" && aws_instance.this.instance_type == "t4g.micro"
    error_message = "The instance uses the AMI from the SSM parameter on a t4g.micro by default."
  }
}

run "the_only_way_in_is_systems_manager" {
  command = apply

  assert {
    condition     = aws_iam_role_policy_attachment.ssm_core.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The instance role must carry the Systems Manager core policy."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "Only EC2 may assume the instance role."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.https) == 2 && alltrue([for rule in aws_vpc_security_group_egress_rule.https : rule.from_port == 443 && rule.to_port == 443 && rule.ip_protocol == "tcp"])
    error_message = "The security group allows HTTPS out and nothing else."
  }

  assert {
    condition     = toset([for rule in aws_vpc_security_group_egress_rule.https : rule.cidr_ipv4]) == toset(var.egress_ipv4_cidrs)
    error_message = "Egress goes only to the given ranges."
  }

  assert {
    condition     = output.port_forward_command == "aws ssm start-session --target i-0123456789abcdef0 --document-name AWS-StartPortForwardingSession --parameters portNumber=3128,localPortNumber=3128"
    error_message = "The port-forward command must target the instance and the proxy port."
  }
}

run "squid_tunnels_https_from_loopback_to_any_host_by_default" {
  command = apply

  assert {
    condition     = strcontains(aws_instance.this.user_data, "http_port 127.0.0.1:3128")
    error_message = "Squid must listen on loopback only."
  }

  assert {
    condition     = strcontains(aws_instance.this.user_data, "http_access deny !CONNECT") && strcontains(aws_instance.this.user_data, "http_access deny !SSL_ports")
    error_message = "Squid must allow only CONNECT to port 443."
  }

  assert {
    condition     = !strcontains(aws_instance.this.user_data, "allowed_destinations")
    error_message = "Without allowed_domains there is no destination list."
  }
}

run "allowed_domains_limit_the_destinations" {
  command = apply

  variables {
    allowed_domains = [".example.com", "api.example.org"]
    proxy_port      = 8888
  }

  assert {
    condition     = strcontains(aws_instance.this.user_data, "acl allowed_destinations dstdomain .example.com api.example.org") && strcontains(aws_instance.this.user_data, "http_access deny !allowed_destinations")
    error_message = "allowed_domains must become a squid dstdomain list that denies everything else."
  }

  assert {
    condition     = strcontains(aws_instance.this.user_data, "http_port 127.0.0.1:8888") && output.proxy_port == 8888
    error_message = "proxy_port must set the squid port."
  }
}

run "rejects_an_x86_instance_type" {
  command = plan

  variables {
    instance_type = "t3.nano"
  }

  expect_failures = [var.instance_type]
}

run "rejects_a_privileged_proxy_port" {
  command = plan

  variables {
    proxy_port = 80
  }

  expect_failures = [var.proxy_port]
}

run "rejects_a_malformed_domain" {
  command = plan

  variables {
    allowed_domains = ["https://example.com"]
  }

  expect_failures = [var.allowed_domains]
}

run "rejects_no_egress" {
  command = plan

  variables {
    egress_ipv4_cidrs = []
  }

  expect_failures = [var.egress_ipv4_cidrs]
}

run "rejects_a_malformed_cidr" {
  command = plan

  variables {
    egress_ipv4_cidrs = ["203.0.113.0"]
  }

  expect_failures = [var.egress_ipv4_cidrs]
}
