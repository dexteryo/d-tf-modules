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

module "cluster" {
  source = "../.."

  name        = "ordering"
  environment = "integration"
  tags        = module.tags.all_tags
}

output "cluster_name" {
  value = module.cluster.cluster_name
}
