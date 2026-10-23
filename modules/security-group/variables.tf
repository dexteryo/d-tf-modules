variable "name" {
  description = "Workload name. The security group is named <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "name_suffix" {
  description = "Optional last part of the name, for example alb or tasks"
  type        = string
  default     = ""
}

variable "description" {
  description = "Description of the security group. Defaults to a sentence built from the name"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC the security group is created in"
  type        = string
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "ingress_rules" {
  description = "Inbound rules keyed by a name that stays the same between runs. Give exactly one source per rule: cidr_ipv4, cidr_ipv6, prefix_list_id or referenced_security_group_id. Leave ports empty for protocol -1"
  type = map(object({
    description                  = string
    protocol                     = optional(string, "tcp")
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.ingress_rules) :
      length([for source in [rule.cidr_ipv4, rule.cidr_ipv6, rule.prefix_list_id, rule.referenced_security_group_id] : source if source != null]) == 1
    ])
    error_message = "Every ingress rule needs exactly one source."
  }

  validation {
    condition     = alltrue([for rule in values(var.ingress_rules) : rule.protocol == "-1" || (rule.from_port != null && rule.to_port != null)])
    error_message = "Ingress rules need from_port and to_port unless the protocol is -1."
  }
}

variable "egress_rules" {
  description = "Outbound rules, same shape as ingress_rules. The default is no outbound traffic at all, so list every destination"
  type = map(object({
    description                  = string
    protocol                     = optional(string, "tcp")
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for rule in values(var.egress_rules) :
      length([for source in [rule.cidr_ipv4, rule.cidr_ipv6, rule.prefix_list_id, rule.referenced_security_group_id] : source if source != null]) == 1
    ])
    error_message = "Every egress rule needs exactly one destination."
  }

  validation {
    condition     = alltrue([for rule in values(var.egress_rules) : rule.protocol == "-1" || (rule.from_port != null && rule.to_port != null)])
    error_message = "Egress rules need from_port and to_port unless the protocol is -1."
  }
}
