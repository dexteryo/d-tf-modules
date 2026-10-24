variable "name" {
  description = "Workload name. The Name tag is <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment, for example integration or production"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Optional last part of the name, for example edge when one workload has several certificates"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "domain_name" {
  description = "Primary name of the certificate, lower case without a trailing dot. A wildcard such as *.example.com is allowed"
  type        = string

  validation {
    condition     = can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_name)) && length(var.domain_name) <= 64
    error_message = "domain_name must be a lower-case DNS name of at most 64 characters, with no trailing dot. Only a leading *. wildcard is allowed."
  }
}

variable "subject_alternative_names" {
  description = "Extra names on the certificate, for example [\"*.example.com\"] or [\"ops.example.com\"]. Must not repeat each other or domain_name"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for san in var.subject_alternative_names :
      can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", san))
    ])
    error_message = "Every subject alternative name must be a lower-case DNS name with no trailing dot. Only a leading *. wildcard is allowed."
  }

  validation {
    condition     = length(var.subject_alternative_names) == length(distinct(var.subject_alternative_names))
    error_message = "subject_alternative_names must not contain duplicates."
  }
}

variable "hosted_zone_id" {
  description = "Public Route 53 hosted zone that holds every name on the certificate. It must already exist and be authoritative for the domain"
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.hosted_zone_id))
    error_message = "hosted_zone_id must be a Route 53 hosted zone ID such as Z0123456789ABCDEFGHIJ."
  }
}

variable "key_algorithm" {
  description = "Key algorithm of the certificate: RSA_2048, EC_prime256v1 or EC_secp384r1"
  type        = string
  default     = "RSA_2048"

  validation {
    condition     = contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm must be RSA_2048, EC_prime256v1 or EC_secp384r1."
  }
}

variable "validation_timeout" {
  description = "How long to wait for ACM to issue the certificate, for example 30m. Terraform fails the apply when it is exceeded"
  type        = string
  default     = "30m"

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.validation_timeout))
    error_message = "validation_timeout must be a whole number followed by s, m or h, for example 30m."
  }
}
