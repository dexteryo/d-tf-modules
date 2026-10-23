terraform {
  required_version = ">= 1.6"
}

module "tags" {
  source = "../.."

  environment = "integration"
  service     = "ordering"
  repository  = "example-org/example-infra"

  optional_tags = {
    Owner = "platform"
  }
}

output "all_tags" {
  value = module.tags.all_tags
}
