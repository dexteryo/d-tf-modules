variable "name" {
  description = "Workload name. The topic is named <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "name_suffix" {
  description = "Optional last part of the name, for example alarms"
  type        = string
  default     = "alarms"
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts the topic. Its key policy must let cloudwatch.amazonaws.com use it (kms:Decrypt and kms:GenerateDataKey*) or alarms cannot publish; the aws/sns key cannot be used for that"
  type        = string
}

variable "allow_cloudwatch_alarms" {
  description = "Let CloudWatch alarms of this account publish to the topic"
  type        = bool
  default     = true
}

variable "email_addresses" {
  description = "Addresses subscribed to the topic. Each owner must confirm the subscription by hand, Terraform cannot"
  type        = list(string)
  default     = []
}

variable "https_endpoints" {
  description = "HTTPS endpoints subscribed to the topic, for example a chat webhook. The endpoint must confirm the subscription"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for endpoint in var.https_endpoints : startswith(endpoint, "https://")])
    error_message = "https_endpoints must start with https://."
  }
}
