variable "environment" {
  description = "Deployment environment, for example integration or production. Used when mandatory_tags has no Environment key"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9-]*$", var.environment))
    error_message = "environment may only contain letters, digits and hyphens."
  }
}

variable "service" {
  description = "Name of the service the resources belong to. Used when mandatory_tags has no Service key"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9-]*$", var.service))
    error_message = "service may only contain letters, digits and hyphens."
  }
}

variable "repository" {
  description = "Repository that owns the Terraform code. Used when mandatory_tags has no Repository key"
  type        = string
  default     = ""
}

variable "mandatory_tags" {
  description = "Map form of the mandatory tags. Keys: Environment, Service, Repository. A key set here wins over the matching individual variable"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.mandatory_tags) : contains(["Environment", "Service", "Repository"], key)])
    error_message = "mandatory_tags may only contain the keys Environment, Service and Repository."
  }
}

variable "optional_tags" {
  description = "Tags from the agreed optional set: Owner, CostCentre, DataClassification, Component"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key in keys(var.optional_tags) : contains(["Owner", "CostCentre", "DataClassification", "Component"], key)])
    error_message = "optional_tags may only contain the keys Owner, CostCentre, DataClassification and Component."
  }
}

variable "custom_tags" {
  description = "Free-form tags. They cannot reuse a mandatory or optional key"
  type        = map(string)
  default     = {}
}
