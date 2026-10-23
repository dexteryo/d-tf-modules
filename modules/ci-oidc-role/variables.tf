variable "name" {
  description = "Workload name. The role is named <name>-<environment>-<name_suffix>"
  type        = string
}

variable "environment" {
  description = "Deployment environment the role belongs to. It is also the default GitHub environment the trust policy accepts"
  type        = string
}

variable "name_suffix" {
  description = "Last part of the role name"
  type        = string
  default     = "deploy"
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "github_repository" {
  description = "Repository allowed to assume the role, as owner/name. Wildcards are refused"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be owner/name without wildcards."
  }
}

variable "github_environment" {
  description = "GitHub environment whose jobs may assume the role. Defaults to the environment variable. Protection rules on that GitHub environment are the deploy gate"
  type        = string
  default     = null

  validation {
    condition     = var.github_environment == null || can(regex("^[A-Za-z0-9_. -]+$", var.github_environment))
    error_message = "github_environment must be a plain environment name without wildcards."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider of the account, arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com. Required unless create_oidc_provider is true"
  type        = string
  default     = null
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. An account has one, so enable this in a single role module only"
  type        = bool
  default     = false
}

variable "ecr_repository_arns" {
  description = "ECR repositories the role may push images to and read from"
  type        = list(string)
  default     = []
}

variable "ecs_service_arns" {
  description = "ECS services the role may update and describe. Registering task definitions is allowed whenever this list is not empty"
  type        = list(string)
  default     = []
}

variable "pass_role_arns" {
  description = "Task and execution role ARNs the role may hand to ECS. Only ecs-tasks.amazonaws.com may receive them"
  type        = list(string)
  default     = []
}

variable "max_session_duration" {
  description = "Seconds a session of the role lasts (3600 to 43200)"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary policy attached to the role"
  type        = string
  default     = null
}
