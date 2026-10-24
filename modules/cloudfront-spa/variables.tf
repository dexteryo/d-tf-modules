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
  description = "Optional last part of the name, for example web when one workload has several distributions"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of the private S3 bucket that holds the app build, the bucket_regional_domain_name output of modules/s3-bucket"
  type        = string
}

variable "aliases" {
  description = "Host names the distribution serves. Needs certificate_arn when not empty"
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ACM certificate in us-east-1 that covers every alias. Null uses the default CloudFront certificate, which only serves the *.cloudfront.net name"
  type        = string
  default     = null
}

variable "web_acl_arn" {
  description = "Web ACL to attach, usually the web_acl_arn output of modules/waf-web-acl. Null leaves the distribution without one"
  type        = string
  default     = null
}

variable "content_security_policy" {
  description = "Content-Security-Policy added to responses that do not carry their own"
  type        = string
  default     = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"
}

variable "allowed_countries" {
  description = "ISO 3166-1 alpha-2 country codes allowed through, for example [\"IE\", \"GB\"]. An empty list means no geo restriction"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for code in var.allowed_countries : can(regex("^[A-Z]{2}$", code))])
    error_message = "allowed_countries must hold two-letter upper-case country codes."
  }
}

variable "price_class" {
  description = "CloudFront price class: PriceClass_100, PriceClass_200 or PriceClass_All"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "access_logs" {
  description = "Send access logs to a KMS-encrypted CloudWatch log group. kms_key_arn is a key in us-east-1 that logs.us-east-1.amazonaws.com may use. Null means no access logs"
  type = object({
    kms_key_arn    = string
    retention_days = optional(number, 7)
  })
  default = null
}

variable "backends" {
  description = <<-EOT
    Paths served by an internal load balancer through a CloudFront VPC origin, keyed by a stable name that is also the function name suffix (letters, digits, hyphens, underscores).
    path_pattern starts with /. origin_domain_name is a custom DNS name covered by the load balancer's listener certificate.
    Backends with the same vpc_origin_id and origin_domain_name share one origin.
    viewer_request_function_code, when set, becomes a CloudFront Function on that behaviour.
    allowed_methods is one of GET,HEAD / GET,HEAD,OPTIONS / all seven methods.
    origin_request_policy is the name of a managed origin request policy without the Managed- prefix.
  EOT
  type = map(object({
    path_pattern                 = string
    vpc_origin_id                = string
    origin_domain_name           = string
    viewer_request_function_code = optional(string)
    allowed_methods              = optional(list(string), ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"])
    origin_request_policy        = optional(string, "AllViewerExceptHostHeader")
  }))
  default = {}

  validation {
    condition     = alltrue([for key, backend in var.backends : can(regex("^[A-Za-z0-9_-]+$", key))])
    error_message = "Backend keys may only contain letters, digits, hyphens and underscores."
  }

  validation {
    condition     = alltrue([for backend in values(var.backends) : startswith(backend.path_pattern, "/")])
    error_message = "Every backend path_pattern must start with /."
  }

  validation {
    condition     = length(distinct([for backend in values(var.backends) : backend.path_pattern])) == length(var.backends)
    error_message = "Backends must not share a path_pattern."
  }

  validation {
    condition     = alltrue([for backend in values(var.backends) : !endswith(backend.origin_domain_name, ".elb.amazonaws.com")])
    error_message = "Use a custom DNS name covered by the load balancer's certificate; no ACM certificate can match *.elb.amazonaws.com."
  }

  validation {
    condition = alltrue([
      for backend in values(var.backends) : anytrue([
        for permitted in [["GET", "HEAD"], ["GET", "HEAD", "OPTIONS"], ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]] :
        toset(backend.allowed_methods) == toset(permitted)
      ])
    ])
    error_message = "allowed_methods must be GET and HEAD, those plus OPTIONS, or all seven methods."
  }
}
