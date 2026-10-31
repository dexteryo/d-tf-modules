variable "name" {
  description = "Workload name. The function is named <name>-<environment>[-<name_suffix>] and its role adds -lambda"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "name_suffix" {
  description = "Optional last part of the name, for example webhook-intake"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "runtime" {
  description = "Lambda runtime, for example nodejs22.x"
  type        = string
}

variable "handler" {
  description = "Handler, <file>.<export>, for example index.handler"
  type        = string
}

variable "architectures" {
  description = "Instruction set of the function"
  type        = list(string)
  default     = ["arm64"]

  validation {
    condition     = length(var.architectures) == 1 && contains(["arm64", "x86_64"], var.architectures[0])
    error_message = "architectures must be [\"arm64\"] or [\"x86_64\"]."
  }
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 10
}

variable "memory_size" {
  description = "Memory in MB"
  type        = number
  default     = 256
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts the environment variables. The role gets kms:Decrypt on it"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Customer-managed key that encrypts the log group. Its key policy must let the CloudWatch Logs service use it"
  type        = string
}

variable "log_retention_days" {
  description = "Days the function's logs are kept"
  type        = number
  default     = 365
}

variable "subnet_ids" {
  description = "Subnets for the function. Empty runs it outside a VPC; set both subnet_ids and security_group_ids to attach it"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security groups for the function when it runs in a VPC"
  type        = list(string)
  default     = []

  validation {
    condition     = (length(var.subnet_ids) == 0) == (length(var.security_group_ids) == 0)
    error_message = "Set both subnet_ids and security_group_ids, or neither."
  }
}

variable "environment_variables" {
  description = "Environment variables. Never put a secret value here; pass the ARN of a secret and read it at run time"
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = "Extra permissions for the function's role, one object per statement. Name resources exactly; the module adds only log writing, kms:Decrypt on kms_key_arn and, in a VPC, the network interface actions"
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "filename" {
  description = "Zip with the code for the first apply. Null uses a placeholder that answers 503 until the deploy workflow ships the real code; the code is ignored after creation"
  type        = string
  default     = null
}
