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

module "bucket_key" {
  source = "../../../kms"

  name        = "ordering"
  environment = "integration"
  name_suffix = "web"
  description = "Ordering integration: web app bucket"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudFrontDecryptsObjects"
    service = "cloudfront.amazonaws.com"
    actions = ["kms:Decrypt"]
    condition = {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudfront::123456789012:distribution/*"]
    }
  }]
}

module "web_bucket" {
  source = "../../../s3-bucket"

  name                        = "ordering"
  environment                 = "integration"
  name_suffix                 = "web"
  kms_key_arn                 = module.bucket_key.kms_key_arn
  cloudfront_distribution_arn = module.web.distribution_arn
  tags                        = module.tags.all_tags
}

module "edge_logs_key" {
  source = "../../../kms"

  providers = { aws = aws.us_east_1 }

  name        = "ordering"
  environment = "integration"
  name_suffix = "edge-logs"
  description = "Ordering integration: web ACL and CloudFront logs"
  tags        = module.tags.all_tags

  service_grants = [{
    sid     = "CloudWatchLogsEncryption"
    service = "logs.us-east-1.amazonaws.com"
    condition = {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-ordering-integration",
        "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/ordering-integration",
      ]
    }
  }]
}

module "web_acl" {
  source = "../../../waf-web-acl"

  providers = { aws = aws.us_east_1 }

  name        = "ordering"
  environment = "integration"
  kms_key_arn = module.edge_logs_key.kms_key_arn
  tags        = module.tags.all_tags
}

module "web" {
  source = "../.."

  providers = { aws = aws.us_east_1 }

  name                        = "ordering"
  environment                 = "integration"
  bucket_regional_domain_name = module.web_bucket.bucket_regional_domain_name
  web_acl_arn                 = module.web_acl.web_acl_arn
  allowed_countries           = ["IE", "GB"]

  access_logs = {
    kms_key_arn = module.edge_logs_key.kms_key_arn
  }

  backends = {
    api = {
      path_pattern       = "/api/*"
      vpc_origin_id      = "vo-0123456789abcdef0"
      origin_domain_name = "origin.example.com"
    }
  }

  tags = module.tags.all_tags
}

output "distribution_domain_name" {
  value = module.web.distribution_domain_name
}
