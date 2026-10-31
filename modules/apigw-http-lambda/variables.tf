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
  description = "Route keys the API accepts, each METHOD /path with no wildcard or path parameter, for example POST /webhooks/acme. Each gets its own invoke permission, so nothing else can reach the function through this API"
  type        = list(string)

  validation {
    condition     = length(var.routes) > 0 && alltrue([for route in var.routes : length(route) <= 60 && can(regex("^(GET|POST|PUT|PATCH|DELETE) /[A-Za-z0-9/_.-]*$", route))])
    error_message = "Each route must be at most 60 characters, METHOD /path using GET, POST, PUT, PATCH or DELETE and only letters, digits, slash, underscore, dot and hyphen in the path."
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
