variable "name" {
  description = "Service name. Resources are named <name>-<environment>"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster the service runs in"
  type        = string
}

variable "vpc_id" {
  description = "VPC the service security group and target group are created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the tasks run in"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to tasks. Keep false unless the subnets have no NAT or endpoints"
  type        = bool
  default     = false
}

variable "cpu" {
  description = "Task CPU units (256, 512, 1024, ...)"
  type        = number
}

variable "memory" {
  description = "Task memory in MiB"
  type        = number
}

variable "cpu_architecture" {
  description = "CPU architecture of the task: X86_64 or ARM64"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "desired_count" {
  description = "Initial number of tasks"
  type        = number
  default     = 1
}

variable "containers" {
  description = "Containers of the task. secrets maps an environment variable name to a Secrets Manager or SSM parameter ARN, optionally suffixed with :json-key::"
  type = list(object({
    name      = string
    image     = string
    essential = optional(bool, true)
    port      = optional(number)
    cpu       = optional(number)
    memory    = optional(number)

    environment = optional(map(string), {})
    secrets     = optional(map(string), {})

    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 0)
    }))

    depends_on = optional(list(object({
      container_name = string
      condition      = string
    })), [])

    read_only_root_filesystem = optional(bool, true)
  }))

  validation {
    condition     = length(var.containers) > 0
    error_message = "At least one container is required."
  }

  validation {
    condition     = length(distinct(var.containers[*].name)) == length(var.containers)
    error_message = "Container names must be unique."
  }

  validation {
    condition     = anytrue([for c in var.containers : c.essential])
    error_message = "At least one container must be essential."
  }

  validation {
    condition = alltrue(flatten([
      for c in var.containers : [
        for d in c.depends_on : contains(["START", "COMPLETE", "SUCCESS", "HEALTHY"], d.condition)
      ]
    ]))
    error_message = "depends_on condition must be START, COMPLETE, SUCCESS or HEALTHY."
  }
}

variable "default_health_check_path" {
  description = "When set, containers with a port and no health_check get a curl check against http://127.0.0.1:<port><path>. The image must contain curl"
  type        = string
  default     = null
}

variable "load_balancer" {
  description = "Attach the service to an existing ALB listener. Set at least one of host_headers or path_patterns"
  type = object({
    container_name        = string
    container_port        = number
    listener_arn          = string
    host_headers          = optional(list(string), [])
    path_patterns         = optional(list(string), [])
    priority              = number
    health_check_path     = optional(string, "/")
    health_check_matcher  = optional(string, "200")
    deregistration_delay  = optional(number, 30)
    alb_security_group_id = string
  })
  default = null

  validation {
    condition     = var.load_balancer == null || length(var.load_balancer.host_headers) + length(var.load_balancer.path_patterns) > 0
    error_message = "load_balancer needs at least one host header or path pattern."
  }
}

variable "task_role_policy_json" {
  description = "IAM policy document (JSON) attached inline to the task role"
  type        = string
  default     = null
}

variable "extra_execution_secret_arns" {
  description = "Additional Secrets Manager or SSM parameter ARNs the execution role may read"
  type        = list(string)
  default     = []
}

variable "extra_ecr_repository_arns" {
  description = "Additional ECR repository ARNs the execution role may pull from. ECR repositories of the container images are derived automatically"
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS keys the execution role may decrypt (secrets encrypted with a customer-managed key)"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "KMS key ARN used to encrypt the service log group"
  type        = string
  default     = null
}

variable "autoscaling" {
  description = "Target tracking autoscaling. Set cpu_target and/or memory_target as utilisation percentages"
  type = object({
    min           = number
    max           = number
    cpu_target    = optional(number)
    memory_target = optional(number)
  })
  default = null
}

variable "enable_execute_command" {
  description = "Enable ECS Exec. Adds the ssmmessages permissions to the task role"
  type        = bool
  default     = false
}

variable "deployment_circuit_breaker" {
  description = "ECS deployment circuit breaker"
  type = object({
    enable   = optional(bool, true)
    rollback = optional(bool, true)
  })
  default = {}
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS ignores failing load balancer health checks after a task starts. Only used with load_balancer"
  type        = number
  default     = 60
}

variable "manage_task_definition_externally" {
  description = "Ignore task_definition and desired_count changes on the service because deploys register new revisions outside Terraform"
  type        = bool
  default     = true
}

variable "capacity_provider_strategy" {
  description = "Capacity provider strategy. Empty runs the service on FARGATE"
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number, 0)
  }))
  default = []
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
