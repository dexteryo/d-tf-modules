variable "name" {
  description = "Workload name. The API is named <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "name_suffix" {
  description = "Optional last part of the name, for example webhooks"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "function_name" {
  description = "Name of the Lambda function every route calls, the function_name output of the lambda module"
  type        = string
}

variable "function_invoke_arn" {
  description = "Invoke ARN of that function, the invoke_arn output of the lambda module"
  type        = string
}

variable "routes" {
  description = "Route keys the API accepts, each METHOD /path, for example POST /webhooks/acme. A path segment may be a named parameter such as {token}, but never a greedy {proxy+} or $default. Each route gets its own invoke permission, so nothing else can reach the function through this API"
  type        = list(string)

  validation {
    condition     = length(var.routes) > 0 && alltrue([for route in var.routes : length(route) <= 60 && can(regex("^(GET|POST|PUT|PATCH|DELETE) /(([A-Za-z0-9_.-]+|\\{[A-Za-z][A-Za-z0-9_]*\\})(/([A-Za-z0-9_.-]+|\\{[A-Za-z][A-Za-z0-9_]*\\}))*)?/?$", route))])
    error_message = "Each route must be at most 60 characters, METHOD /path using GET, POST, PUT, PATCH or DELETE. Path segments use letters, digits, underscore, dot and hyphen, or are a whole named parameter such as {token}; greedy parameters and $default are refused."
  }
}

variable "logs_kms_key_arn" {
  description = "Customer-managed key that encrypts the access log group. Its key policy must let the CloudWatch Logs service use it"
  type        = string
}

variable "log_retention_days" {
  description = "Days the access logs are kept"
  type        = number
  default     = 365
}

variable "throttling_rate_limit" {
  description = "Steady requests per second, applied to the stage and to every route"
  type        = number
  default     = 25
}

variable "throttling_burst_limit" {
  description = "Burst requests, applied to the stage and to every route"
  type        = number
  default     = 50
}

variable "integration_timeout_ms" {
  description = "How long API Gateway waits for the function. The HTTP API maximum is 30000"
  type        = number
  default     = 5000

  validation {
    condition     = var.integration_timeout_ms >= 50 && var.integration_timeout_ms <= 30000
    error_message = "integration_timeout_ms must be between 50 and 30000."
  }
}

variable "custom_domain" {
  description = "Optional regional custom domain for the API: domain_name (lower case, no trailing dot) and certificate_arn (an ACM certificate for that name in the API's region). The domain root maps to the default stage. The execute-api URL keeps working. Create the DNS record from the custom_domain_target output"
  type = object({
    domain_name     = string
    certificate_arn = string
  })
  default = null

  validation {
    condition     = var.custom_domain == null || (can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.custom_domain.domain_name)) && can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[A-Za-z0-9-]+$", var.custom_domain.certificate_arn)))
    error_message = "custom_domain.domain_name must be a lower-case host name without a trailing dot, and custom_domain.certificate_arn an ACM certificate ARN."
  }
}
