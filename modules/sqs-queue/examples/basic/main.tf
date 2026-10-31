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
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "jobs"
  description = "Encrypts the ordering job queue"
  tags        = module.tags.all_tags
}

module "alarm_topic_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "alarms"
  description = "Encrypts the ordering alarm topic"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchAlarms"
    service = "cloudwatch.amazonaws.com"
    actions = ["kms:Decrypt", "kms:GenerateDataKey*"]
  }]
}

module "alarm_topic" {
  source = "../../../sns-topic"

  name        = "ordering"
  environment = "integration"
  tags        = module.tags.all_tags
  kms_key_arn = module.alarm_topic_key.kms_key_arn
}

module "jobs" {
  source = "../.."

  name          = "ordering"
  environment   = "integration"
  name_suffix   = "jobs"
  tags          = module.tags.all_tags
  kms_key_arn   = module.kms.kms_key_arn
  alarm_actions = [module.alarm_topic.topic_arn]
}

output "queue_url" {
  value = module.jobs.queue_url
}

output "dlq_arn" {
  value = module.jobs.dlq_arn
}
