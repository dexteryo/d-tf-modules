terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

module "data_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "data"
  description = "Ordering integration: database storage and secrets"
  tags        = module.tags.all_tags
}

module "logs_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "logs"
  description = "Ordering integration: log groups"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.eu-west-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:*"]
    }
  }]
}

module "vpc" {
  source = "../../../vpc"

  name               = "ordering"
  environment        = "integration"
  cidr_block         = "10.20.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  logs_kms_key_arn   = module.logs_key.kms_key_arn
  tags               = module.tags.all_tags
}

module "app_security_group" {
  source = "../../../security-group"

  name        = "ordering"
  environment = "integration"
  name_suffix = "app"
  vpc_id      = module.vpc.vpc_id
  tags        = module.tags.all_tags
}

module "proxy_security_group" {
  source = "../../../security-group"

  name        = "ordering"
  environment = "integration"
  name_suffix = "proxy"
  vpc_id      = module.vpc.vpc_id
  tags        = module.tags.all_tags

  ingress_rules = {
    from_app = {
      description                  = "PostgreSQL from the application"
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.app_security_group.security_group_id
    }
  }
}

module "db_security_group" {
  source = "../../../security-group"

  name        = "ordering"
  environment = "integration"
  name_suffix = "db"
  vpc_id      = module.vpc.vpc_id
  tags        = module.tags.all_tags

  ingress_rules = {
    from_proxy = {
      description                  = "PostgreSQL from the proxy"
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.proxy_security_group.security_group_id
    }
  }
}

module "database" {
  source = "../.."

  name               = "ordering"
  environment        = "integration"
  subnet_ids         = module.vpc.isolated_subnet_ids
  security_group_ids = [module.db_security_group.security_group_id]
  data_kms_key_arn   = module.data_key.kms_key_arn
  logs_kms_key_arn   = module.logs_key.kms_key_arn
  tags               = module.tags.all_tags

  database_roles = {
    ordering_api = { database = "ordering" }
  }

  proxy = {
    role_names         = ["ordering_api"]
    security_group_ids = [module.proxy_security_group.security_group_id]
  }
}

output "proxy_endpoint" {
  value = module.database.proxy_endpoint
}
