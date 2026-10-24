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

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "tags" {
  source = "../../../tags"

  environment = "integration"
  service     = "ordering"
  repository  = "example-org/example-infra"
}

module "load_balancer_certificate" {
  source = "../.."

  name                      = "ordering"
  environment               = "integration"
  name_suffix               = "alb"
  domain_name               = "example.com"
  subject_alternative_names = ["*.example.com"]
  hosted_zone_id            = "Z0123456789ABCDEFGHIJ"
  tags                      = module.tags.all_tags
}

module "cloudfront_certificate" {
  source = "../.."

  providers = { aws = aws.us_east_1 }

  name                      = "ordering"
  environment               = "integration"
  name_suffix               = "edge"
  domain_name               = "example.com"
  subject_alternative_names = ["*.example.com"]
  hosted_zone_id            = "Z0123456789ABCDEFGHIJ"
  key_algorithm             = "EC_prime256v1"
  tags                      = module.tags.all_tags
}

output "load_balancer_certificate_arn" {
  value = module.load_balancer_certificate.certificate_arn
}

output "cloudfront_certificate_arn" {
  value = module.cloudfront_certificate.certificate_arn
}
