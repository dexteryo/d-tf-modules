variable "name" {
  description = "Workload name. Resources are named <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "name_suffix" {
  description = "Optional last part of the name"
  type        = string
  default     = "egress-proxy"
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC the proxy runs in"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the instance. Its route to the internet (a NAT gateway) decides the source IP partners see"
  type        = string
}

variable "egress_ipv4_cidrs" {
  description = "IPv4 ranges the instance may reach on HTTPS. Systems Manager must be among them, either the internet (0.0.0.0/0) or a VPC with ssm, ssmmessages and ec2messages interface endpoints, and so must the package repositories the instance updates from at boot"
  type        = list(string)

  validation {
    condition     = length(var.egress_ipv4_cidrs) > 0 && alltrue([for cidr in var.egress_ipv4_cidrs : can(cidrnetmask(cidr))])
    error_message = "egress_ipv4_cidrs must hold at least one IPv4 CIDR block; without one the instance cannot reach Systems Manager."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts the root volume. Its key policy must let IAM policies in this account use it, or EC2 cannot launch the instance"
  type        = string
}

variable "instance_type" {
  description = "Graviton instance type; the AMI is arm64"
  type        = string
  default     = "t4g.nano"

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a Graviton (arm64) type such as t4g.nano."
  }
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that holds the Amazon Linux 2023 arm64 AMI ID"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

variable "proxy_port" {
  description = "Port squid listens on, on the instance's loopback only"
  type        = number
  default     = 3128

  validation {
    condition     = var.proxy_port >= 1024 && var.proxy_port <= 65535 && floor(var.proxy_port) == var.proxy_port
    error_message = "proxy_port must be a whole number from 1024 to 65535."
  }
}

variable "allowed_domains" {
  description = "Destinations the proxy may tunnel to, in squid dstdomain form (a leading dot matches subdomains, for example .example.com). Empty allows any host"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for domain in var.allowed_domains : can(regex("^\\.?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", domain))])
    error_message = "allowed_domains must be lower-case host names, optionally with a leading dot."
  }
}
