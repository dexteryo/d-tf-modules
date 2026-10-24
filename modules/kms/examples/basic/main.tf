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

module "kms" {
  source = "../.."

  name        = "ordering"
  environment = "integration"
  name_suffix = "app"
  description = "Ordering integration: secrets and task logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.eu-west-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/ordering-integration"]
    }
  }]
}

output "kms_key_arn" {
  value = module.kms.kms_key_arn
}
