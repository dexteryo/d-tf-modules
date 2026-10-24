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
  region = "us-east-1"
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
  name_suffix = "edge-logs"
  description = "Ordering integration: web ACL logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.us-east-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-ordering-integration"]
    }
  }]
}

module "web_acl" {
  source = "../.."

  name                     = "ordering"
  environment              = "integration"
  kms_key_arn              = module.logs_key.kms_key_arn
  rate_limit_per_5_minutes = 500
  tags                     = module.tags.all_tags
}

output "web_acl_arn" {
  value = module.web_acl.web_acl_arn
}
