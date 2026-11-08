variable "name" {
  description = "Base name for the schedule group, schedules and roles"
  type        = string
}

variable "environment" {
  description = "Environment name, appended to the base name"
  type        = string
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "timezone" {
  description = "IANA time zone the cron expressions are read in, for example Asia/Ho_Chi_Minh. Daylight saving changes are followed"
  type        = string
  default     = "UTC"

  validation {
    condition     = can(regex("^(UTC|[A-Za-z]+(/[A-Za-z0-9_+-]+)+)$", var.timezone))
    error_message = "timezone must be UTC or an IANA zone name such as Asia/Ho_Chi_Minh."
  }
}

variable "stop_schedule" {
  description = "EventBridge Scheduler cron expression for stopping, for example cron(0 23 ? * MON-FRI *). Services scale to zero and databases stop at the same time"
  type        = string

  validation {
    condition     = can(regex("^cron\\([^()]+\\)$", var.stop_schedule))
    error_message = "stop_schedule must be a cron(...) expression."
  }
}

variable "start_schedule" {
  description = "Cron expressions for starting: databases first, services later, because a service cannot boot while its database is still starting (allow about 15 minutes). Null keeps the start schedules disabled, so the environment only starts when an operator starts it"
  type = object({
    databases = string
    services  = string
  })
  default = null

  validation {
    condition     = var.start_schedule == null ? true : alltrue([for expression in [var.start_schedule.databases, var.start_schedule.services] : can(regex("^cron\\([^()]+\\)$", expression))])
    error_message = "start_schedule.databases and start_schedule.services must be cron(...) expressions."
  }
}

variable "ecs_services" {
  description = "ECS services to scale to zero and back, keyed by a short stable name. desired_count is the count the start restores. A Terraform-managed service needs ignore_desired_count = true in ecs-service"
  type = map(object({
    cluster_name  = string
    service_name  = string
    desired_count = optional(number, 1)
  }))
  default = {}

  validation {
    condition     = alltrue([for key, service in var.ecs_services : can(regex("^[a-z0-9-]{1,16}$", key)) && service.desired_count >= 1 && floor(service.desired_count) == service.desired_count])
    error_message = "ecs_services keys must be 1 to 16 lower-case letters, digits or hyphens, and desired_count must be a whole number of at least 1."
  }
}

variable "db_instances" {
  description = "RDS DB instance identifiers to stop and start, keyed by a short stable name. Instances in a cluster and Multi-AZ SQL Server instances cannot be stopped"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key, identifier in var.db_instances : can(regex("^[a-z0-9-]{1,16}$", key)) && can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,62}$", identifier))])
    error_message = "db_instances keys must be 1 to 16 lower-case letters, digits or hyphens, and values must be DB instance identifiers."
  }
}

variable "operator" {
  description = "Create a role that one GitHub repository environment can assume through OIDC to read these schedules and start or stop the same targets on demand. Null creates no role"
  type = object({
    github_repository  = string
    github_environment = string
    oidc_provider_arn  = string
    github_immutable_ids = optional(object({
      owner_id      = number
      repository_id = number
    }))
  })
  default = null

  validation {
    condition     = var.operator == null ? true : can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.operator.github_repository)) && can(regex("^[A-Za-z0-9_. -]+$", var.operator.github_environment))
    error_message = "operator.github_repository must be owner/name and operator.github_environment a plain environment name, both without wildcards."
  }

  validation {
    condition     = var.operator == null ? true : can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.operator.oidc_provider_arn))
    error_message = "operator.oidc_provider_arn must be the ARN of the account's GitHub OIDC provider."
  }
}
