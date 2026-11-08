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

module "schedule" {
  source = "../.."

  name          = "ordering"
  environment   = "integration"
  tags          = module.tags.all_tags
  timezone      = "Europe/Dublin"
  stop_schedule = "cron(0 20 ? * MON-FRI *)"

  start_schedule = {
    databases = "cron(40 7 ? * MON-FRI *)"
    services  = "cron(55 7 ? * MON-FRI *)"
  }

  ecs_services = {
    api = {
      cluster_name = "ordering-integration"
      service_name = "ordering-api-integration"
    }
  }

  db_instances = {
    main = "ordering-integration-postgres"
  }

  operator = {
    github_repository  = "example-org/example-app"
    github_environment = "integration"
    oidc_provider_arn  = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
}

output "schedule_group_name" {
  value = module.schedule.schedule_group_name
}

output "operator_role_arn" {
  value = module.schedule.operator_role_arn
}
