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

module "alarms" {
  source = "../.."

  name          = "ordering"
  environment   = "integration"
  tags          = module.tags.all_tags
  cluster_name  = "ordering-integration"
  service_name  = "ordering-integration"
  alarm_actions = ["arn:aws:sns:eu-west-1:123456789012:ordering-alarms"]

  running_tasks = {
    enabled = true
    minimum = 2
  }

  load_balancer = {
    load_balancer_arn_suffix = "app/example/0123456789abcdef"
    target_group_arn_suffix  = "targetgroup/example/0123456789abcdef"
  }
}

output "alarm_arns" {
  value = module.alarms.alarm_arns
}
