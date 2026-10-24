terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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

module "cluster" {
  source = "../../../ecs-cluster"

  name        = "ordering"
  environment = "integration"
  tags        = module.tags.all_tags
}

module "task_security_group" {
  source = "../../../security-group"

  name        = "ordering"
  environment = "integration"
  vpc_id      = "vpc-0123456789abcdef0"
  tags        = module.tags.all_tags

  egress_rules = {
    https = {
      description = "HTTPS to AWS APIs and the registry"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "10.0.0.0/8"
    }
  }
}

module "service" {
  source = "../.."

  name               = "ordering"
  environment        = "integration"
  tags               = module.tags.all_tags
  cluster_arn        = module.cluster.cluster_arn
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids = [module.task_security_group.security_group_id]

  cpu    = 512
  memory = 1024

  containers = [{
    name  = "app"
    image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/example/app:bootstrap"
    port  = 8080
  }]
}

output "service_name" {
  value = module.service.service_name
}
