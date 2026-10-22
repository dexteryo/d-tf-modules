variable "name" {
  description = "Cluster name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "default_capacity_provider_strategy" {
  description = "Default capacity provider strategy for services that do not set their own"
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number, 0)
  }))
  default = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 0
    }
  ]

  validation {
    condition     = alltrue([for s in var.default_capacity_provider_strategy : contains(["FARGATE", "FARGATE_SPOT"], s.capacity_provider)])
    error_message = "capacity_provider must be FARGATE or FARGATE_SPOT."
  }
}

variable "enable_execute_command_logging" {
  description = "Send ECS Exec session logs to a dedicated CloudWatch log group"
  type        = bool
  default     = false
}

variable "execute_command_kms_key_arn" {
  description = "KMS key ARN used to encrypt ECS Exec sessions"
  type        = string
  default     = null
}

variable "execute_command_log_kms_key_arn" {
  description = "KMS key ARN used to encrypt the ECS Exec log group"
  type        = string
  default     = null
}

variable "execute_command_log_retention_days" {
  description = "Retention of the ECS Exec log group in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
