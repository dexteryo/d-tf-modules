terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "tags" {
  source = "../../../tags"

  environment = "shared"
  service     = "ordering"
  repository  = "example-org/example-infra"
}

module "ecr" {
  for_each = toset(["ordering-agent", "ordering-mcp"])
  source   = "../.."

  name = each.key
  tags = module.tags.all_tags
}

output "repository_urls" {
  value = { for name, repository in module.ecr : name => repository.repository_url }
}
