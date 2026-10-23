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

module "task_security_group" {
  source = "../../../security-group"

  name        = "ordering"
  environment = "integration"
  vpc_id      = "vpc-0123456789abcdef0"
  tags        = module.tags.all_tags

  ingress_rules = {
    from-alb = {
      description                  = "Application port from the load balancer"
      from_port                    = 8788
      to_port                      = 8788
      referenced_security_group_id = module.alb.alb_security_group_id
    }
  }
}

module "alb" {
  source = "../.."

  name         = "ordering"
  environment  = "integration"
  vpc_id       = "vpc-0123456789abcdef0"
  subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  tags         = module.tags.all_tags
  idle_timeout = 120

  cloudfront_only = true

  listeners = {
    public = {
      port            = 443
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    }
  }

  egress_rules = {
    to-tasks = {
      description                  = "Application port of the tasks"
      from_port                    = 8788
      to_port                      = 8788
      referenced_security_group_id = module.task_security_group.security_group_id
    }
  }
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}
