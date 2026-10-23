output "all_tags" {
  description = "Mandatory, optional and custom tags merged. Pass it to the tags input of every other module"
  value       = merge(var.custom_tags, var.optional_tags, local.mandatory_tags)

  precondition {
    condition     = length(local.missing_mandatory) == 0
    error_message = "Environment, Service and Repository must all have a value; missing: ${join(", ", local.missing_mandatory)}."
  }

  precondition {
    condition     = length(local.clashing_custom) == 0
    error_message = "custom_tags must not reuse a mandatory or optional key; clashing: ${join(", ", local.clashing_custom)}."
  }
}

output "mandatory_tags" {
  description = "Environment, Service, Repository and ManagedBy"
  value       = local.mandatory_tags
}

output "optional_tags" {
  description = "The optional tags as given"
  value       = var.optional_tags
}

output "custom_tags" {
  description = "The custom tags as given"
  value       = var.custom_tags
}

output "environment" {
  description = "Lower-case environment, for naming resources"
  value       = local.environment
}

output "service" {
  description = "Lower-case service name, for naming resources"
  value       = local.service
}

output "repository" {
  description = "Repository that owns the code"
  value       = local.repository
}
