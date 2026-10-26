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

module "deploy_role" {
  source = "../.."

  name              = "ordering"
  environment       = "integration"
  tags              = module.tags.all_tags
  github_repository = "example-org/example-app"

  oidc_provider_arn   = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  ecr_repository_arns = ["arn:aws:ecr:eu-west-1:123456789012:repository/ordering-agent"]
  ecs_service_arns    = ["arn:aws:ecs:eu-west-1:123456789012:service/ordering-integration/ordering-integration"]
  pass_role_arns = [
    "arn:aws:iam::123456789012:role/ordering-integration-execution",
    "arn:aws:iam::123456789012:role/ordering-integration-task",
  ]

  static_site_bucket_arns      = ["arn:aws:s3:::ordering-integration-web"]
  static_site_kms_key_arns     = ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
  cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE"]
}

output "role_arn" {
  value = module.deploy_role.role_arn
}
