terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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
  description = "Encrypts the function's environment variables"
  tags        = module.tags.all_tags
}

module "logs_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "logs"
  description = "Encrypts the function's logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.eu-west-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/ordering-integration-intake"]
    }
  }]
}

module "intake" {
  source = "../.."

  name             = "ordering"
  environment      = "integration"
  name_suffix      = "intake"
  tags             = module.tags.all_tags
  runtime          = "nodejs22.x"
  handler          = "intake.handler"
  kms_key_arn      = module.data_key.kms_key_arn
  logs_kms_key_arn = module.logs_key.kms_key_arn

  policy_statements = [{
    sid       = "SendToQueue"
    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:eu-west-1:123456789012:ordering-integration-jobs"]
  }]
}

output "function_name" {
  value = module.intake.function_name
}
