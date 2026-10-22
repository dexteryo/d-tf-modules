variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "integration"
}

variable "vpc_id" {
  description = "Placeholder VPC ID"
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "private_subnet_ids" {
  description = "Placeholder private subnet IDs"
  type        = list(string)
  default     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

variable "listener_arn" {
  description = "Placeholder HTTPS listener ARN of an existing ALB"
  type        = string
  default     = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/example/0123456789abcdef/0123456789abcdef"
}

variable "alb_security_group_id" {
  description = "Placeholder security group ID of the ALB"
  type        = string
  default     = "sg-0123456789abcdef0"
}

variable "agent_host_header" {
  description = "Placeholder host name routed to the agent"
  type        = string
  default     = "ordering-agent.example.com"
}

variable "ecr_registry" {
  description = "Placeholder ECR registry host"
  type        = string
  default     = "123456789012.dkr.ecr.eu-west-1.amazonaws.com"
}
