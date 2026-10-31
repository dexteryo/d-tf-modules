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

module "logs_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "logs"
  description = "Encrypts the function and API access logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.eu-west-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/ordering-integration-intake",
        "arn:aws:logs:eu-west-1:123456789012:log-group:/ordering-integration-webhooks/api/access",
      ]
    }
  }]
}

module "intake" {
  source = "../../../lambda"

  name             = "ordering"
  environment      = "integration"
  name_suffix      = "intake"
  tags             = module.tags.all_tags
  runtime          = "nodejs22.x"
  handler          = "intake.handler"
  logs_kms_key_arn = module.logs_key.kms_key_arn
}

module "webhooks" {
  source = "../.."

  name                = "ordering"
  environment         = "integration"
  name_suffix         = "webhooks"
  tags                = module.tags.all_tags
  function_name       = module.intake.function_name
  function_invoke_arn = module.intake.invoke_arn
  routes              = ["POST /webhooks/acme", "POST /webhooks/globex"]
  logs_kms_key_arn    = module.logs_key.kms_key_arn
}

output "invoke_url" {
  value = module.webhooks.invoke_url
}
