variable "name" {
  description = "Workload name. The instance is named <name>-<environment>[-<name_suffix>]-postgres"
  type        = string
}

variable "environment" {
  description = "Deployment environment, for example integration or production"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Optional part of the name, for example reporting when one workload has several databases"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "Isolated subnets, in at least two zones, for the instance and the proxy"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must list subnets in at least two zones."
  }
}

variable "security_group_ids" {
  description = "Security groups of the instance. They decide who can connect; build them with the security-group module"
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "security_group_ids must contain at least one security group, or RDS falls back to the VPC default group."
  }
}

variable "data_kms_key_arn" {
  description = "Key that encrypts storage, backups, Performance Insights and the secrets"
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Key that encrypts the PostgreSQL log groups"
  type        = string
}

variable "master_username" {
  description = "Administrator user name. RDS creates and manages its password in Secrets Manager. Changing it replaces the instance"
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "PostgreSQL major version; AWS applies minor versions"
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "Instance class"
  type        = string
  default     = "db.t4g.medium"
}

variable "multi_az" {
  description = "Multi-AZ instance"
  type        = bool
  default     = false
}

variable "allocated_storage_gb" {
  description = "Initial storage in GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Ceiling for storage autoscaling in GiB"
  type        = number
  default     = 200
}

variable "backup_retention_days" {
  description = "Days of automated backups, which is also the window for point-in-time restore (1 to 35)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "backup_window" {
  description = "Daily backup window in UTC"
  type        = string
  default     = "05:00-06:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC"
  type        = string
  default     = "sun:06:30-sun:07:30"
}

variable "deletion_protection" {
  description = "Block deletion of the instance"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the snapshot taken when the instance is destroyed"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Days to keep the PostgreSQL and upgrade logs"
  type        = number
  default     = 365
}

variable "free_storage_alarm_bytes" {
  description = "Free storage below which the alarm fires, in bytes"
  type        = number
  default     = 5368709120
}

variable "alarm_topic_arns" {
  description = "SNS topics notified when the alarm fires and when it clears"
  type        = list(string)
  default     = []
}

variable "database_roles" {
  description = "One entry per application role, keyed by role name: the database it belongs to. Each gets a generated password in its own Secrets Manager secret. This module does not create the roles or databases inside PostgreSQL; a bootstrap step in the caller does"
  type = map(object({
    database = string
  }))
  default = {}
}

variable "proxy" {
  description = "RDS Proxy in front of the instance. role_names are the database_roles the proxy may sign in as, and security_group_ids are the proxy's own groups. Null for no proxy"
  type = object({
    role_names          = set(string)
    security_group_ids  = list(string)
    idle_client_timeout = optional(number, 1800)
  })
  default = null

  validation {
    condition     = var.proxy == null || (length(var.proxy.role_names) >= 1 && length(var.proxy.security_group_ids) >= 1)
    error_message = "proxy needs at least one role name and one security group."
  }
}
