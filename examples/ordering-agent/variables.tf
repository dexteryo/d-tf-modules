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

variable "repository" {
  description = "Repository that owns this configuration, as owner/name"
  type        = string
  default     = "example-org/example-infra"
}

variable "vpc_id" {
  description = "Placeholder VPC ID"
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "vpc_cidr" {
  description = "Placeholder CIDR of the VPC; the tasks may only reach this range, so the VPC needs endpoints for ECR, Secrets Manager, CloudWatch Logs and DynamoDB"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_ids" {
  description = "Placeholder public subnet IDs for the load balancer"
  type        = list(string)
  default     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

variable "private_subnet_ids" {
  description = "Placeholder private subnet IDs for the tasks"
  type        = list(string)
  default     = ["subnet-0a1b2c3d4e5f60718", "subnet-08f7e6d5c4b3a2910"]
}

variable "certificate_arn" {
  description = "Placeholder ACM certificate ARN for the load balancer listener"
  type        = string
  default     = "arn:aws:acm:eu-west-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
}

variable "agent_host_header" {
  description = "Placeholder host name routed to the agent"
  type        = string
  default     = "ordering-agent.example.com"
}

variable "github_repository" {
  description = "Repository whose workflows deploy the service, as owner/name"
  type        = string
  default     = "example-org/example-app"
}

variable "oidc_provider_arn" {
  description = "Placeholder ARN of the GitHub OIDC identity provider of the account"
  type        = string
  default     = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

variable "alarm_email_addresses" {
  description = "Addresses that receive the alarms; each must confirm the subscription"
  type        = list(string)
  default     = ["alerts@example.com"]
}
