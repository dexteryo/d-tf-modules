terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "tags" {
  source = "../../../tags"

  environment = "integration"
  service     = "ordering"
  repository  = "example-org/example-infra"
}

module "load_balancer_group" {
  source = "../.."

  name        = "ordering"
  environment = "integration"
  name_suffix = "alb"
  vpc_id      = "vpc-0123456789abcdef0"
  tags        = module.tags.all_tags
}

module "task_group" {
  source = "../.."

  name        = "ordering"
  environment = "integration"
  vpc_id      = "vpc-0123456789abcdef0"
  tags        = module.tags.all_tags

  ingress_rules = {
    from-alb = {
      description                  = "Application port from the load balancer"
      from_port                    = 8788
      to_port                      = 8788
      referenced_security_group_id = module.load_balancer_group.security_group_id
    }
  }

  egress_rules = {
    https = {
      description = "HTTPS to AWS APIs and the registry"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "10.0.0.0/8"
    }
  }
}

output "task_security_group_id" {
  value = module.task_group.security_group_id
}
