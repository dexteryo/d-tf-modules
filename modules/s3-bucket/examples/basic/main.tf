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
  name_suffix = "documents"
  description = "Ordering integration: documents bucket"
  tags        = module.tags.all_tags
}

module "documents" {
  source = "../.."

  name                       = "ordering"
  environment                = "integration"
  name_suffix                = "documents"
  kms_key_arn                = module.kms.kms_key_arn
  object_lock_retention_days = 1
  tags                       = module.tags.all_tags
}

output "bucket_id" {
  value = module.documents.bucket_id
}
