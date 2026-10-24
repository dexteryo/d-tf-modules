variable "name" {
  description = "Workload name. Resources are named <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment, for example integration or production"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Optional last part of the name, for example edge when one workload has several web ACLs"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Key in the module provider region (us-east-1) that encrypts the WAF log group"
  type        = string
}

variable "log_retention_days" {
  description = "Days to keep WAF logs in CloudWatch. They hold client IPs, so keep them short"
  type        = number
  default     = 7
}

variable "managed_rule_groups" {
  description = "Managed rule groups to evaluate, each with a unique name and a unique priority. Lower priorities run first"
  type = list(object({
    name        = string
    priority    = number
    vendor_name = optional(string, "AWS")
  }))
  default = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 10 },
    { name = "AWSManagedRulesAnonymousIpList", priority = 15 },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 20 },
    { name = "AWSManagedRulesCommonRuleSet", priority = 30 },
  ]

  validation {
    condition     = length(distinct([for group in var.managed_rule_groups : group.name])) == length(var.managed_rule_groups)
    error_message = "managed_rule_groups must not repeat a rule group name."
  }

  validation {
    condition     = length(distinct([for group in var.managed_rule_groups : group.priority])) == length(var.managed_rule_groups)
    error_message = "managed_rule_groups must not repeat a priority."
  }
}

variable "rate_limit_per_5_minutes" {
  description = "Requests one IP may send in 5 minutes before WAF blocks it. Null turns the rate rule off. The rule runs after every managed rule group"
  type        = number
  default     = 1000

  validation {
    condition     = var.rate_limit_per_5_minutes == null || coalesce(var.rate_limit_per_5_minutes, 10) >= 10
    error_message = "rate_limit_per_5_minutes must be null or at least 10, the lowest limit WAF accepts."
  }
}

variable "redacted_headers" {
  description = "Request headers whose values are replaced in the WAF logs"
  type        = list(string)
  default     = ["authorization", "cookie"]
}

variable "redact_uri_path" {
  description = "Replace the request path in the WAF logs"
  type        = bool
  default     = true
}

variable "redact_query_string" {
  description = "Replace the query string in the WAF logs"
  type        = bool
  default     = true
}
