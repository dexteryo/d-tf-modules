locals {
  environment = lower(lookup(var.mandatory_tags, "Environment", "") != "" ? var.mandatory_tags["Environment"] : var.environment)
  service     = lower(lookup(var.mandatory_tags, "Service", "") != "" ? var.mandatory_tags["Service"] : var.service)
  repository  = trimspace(lookup(var.mandatory_tags, "Repository", "") != "" ? var.mandatory_tags["Repository"] : var.repository)

  mandatory_tags = {
    Environment = local.environment
    Service     = local.service
    Repository  = local.repository
    ManagedBy   = "terraform"
  }

  missing_mandatory = [for key in ["Environment", "Service", "Repository"] : key if local.mandatory_tags[key] == ""]
  reserved_keys     = ["Environment", "Service", "Repository", "ManagedBy", "Owner", "CostCentre", "DataClassification", "Component"]
  clashing_custom   = [for key in keys(var.custom_tags) : key if contains(local.reserved_keys, key)]
}
