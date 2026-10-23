variable "name" {
  description = "Workload name. The load balancer is named <name>-<environment>, at most 32 characters"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC of the load balancer and its security group"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets of the load balancer, in at least two availability zones"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "The load balancer needs subnets in at least two availability zones."
  }
}

variable "internal" {
  description = "Create an internal load balancer instead of an internet-facing one"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Seconds a connection may stay idle. Raise it for server-sent events"
  type        = number
  default     = 60
}

variable "drop_invalid_header_fields" {
  description = "Drop requests with malformed HTTP header fields"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Refuse to delete the load balancer until the protection is turned off"
  type        = bool
  default     = true
}

variable "access_logs" {
  description = "Write access logs to an S3 bucket the load balancer may write to. The bucket and its policy are not created here"
  type = object({
    bucket = string
    prefix = optional(string)
  })
  default = null
}

variable "ingress_port" {
  description = "Port the ingress options below open"
  type        = number
  default     = 443
}

variable "cloudfront_only" {
  description = "Accept traffic from CloudFront's origin-facing prefix list only. Combine with a secret header rule so other CloudFront distributions cannot reach the origin"
  type        = bool
  default     = false
}

variable "ingress_cidrs" {
  description = "IPv4 ranges that may reach the load balancer"
  type        = list(string)
  default     = []
}

variable "ingress_prefix_list_ids" {
  description = "Managed prefix lists that may reach the load balancer"
  type        = list(string)
  default     = []
}

variable "egress_rules" {
  description = "Outbound rules of the load balancer security group, same shape as in the security-group module. List the target security group and port of every service the load balancer forwards to"
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
}

variable "listeners" {
  description = "HTTPS listeners keyed by a name that stays the same between runs. Without default_target_group_arn the listener answers every request with a fixed 403, so a request only reaches a service through a rule"
  type = map(object({
    port                     = number
    certificate_arn          = string
    ssl_policy               = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    default_target_group_arn = optional(string)
  }))
  default = {}
}

variable "header_forward_rules" {
  description = "Rules that forward requests carrying a given header to a target group. The header value comes from header_values under the same key"
  type = map(object({
    listener         = string
    priority         = number
    header_name      = string
    target_group_arn = string
  }))
  default = {}
}

variable "header_values" {
  description = "Secret header values of header_forward_rules, keyed like the rules"
  type        = map(string)
  default     = {}
  sensitive   = true
}
