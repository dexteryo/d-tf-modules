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

module "vpc" {
  source = "../../../vpc"

  name               = "ordering"
  environment        = "integration"
  tags               = module.tags.all_tags
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b"]
  logs_kms_key_arn   = module.kms.kms_key_arn
}

module "kms" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "data"
  description = "Encrypts the ordering data"
  tags        = module.tags.all_tags
}

module "egress_proxy" {
  source = "../.."

  name              = "ordering"
  environment       = "integration"
  tags              = module.tags.all_tags
  vpc_id            = module.vpc.vpc_id
  subnet_id         = module.vpc.private_subnet_ids[0]
  kms_key_arn       = module.kms.kms_key_arn
  egress_ipv4_cidrs = ["203.0.113.0/24"]
  allowed_domains   = [".example.com"]
}

output "port_forward_command" {
  value = module.egress_proxy.port_forward_command
}
