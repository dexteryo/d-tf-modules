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

module "logs_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "logs"
  description = "Ordering integration: VPC flow logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.eu-west-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:/ordering-integration/vpc-flow"]
    }
  }]
}

module "vpc" {
  source = "../.."

  name                        = "ordering"
  environment                 = "integration"
  cidr_block                  = "10.20.0.0/16"
  availability_zones          = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  logs_kms_key_arn            = module.logs_key.kms_key_arn
  interface_endpoint_services = ["ecr.api", "ecr.dkr", "logs", "secretsmanager"]
  tags                        = module.tags.all_tags
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "nat_eips" {
  value = module.vpc.nat_eips
}
