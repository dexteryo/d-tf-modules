variable "name" {
  description = "Workload name. Resources are named <name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment, for example integration or production"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Optional last part of the name, for example edge when one workload has several networks"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "cidr_block" {
  description = "CIDR of the VPC. It must be a /16 so the fixed subnet layout fits"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr_block)) && try(tonumber(split("/", var.cidr_block)[1]) == 16, false)
    error_message = "cidr_block must be a valid IPv4 CIDR with a /16 prefix."
  }
}

variable "availability_zones" {
  description = "Zones to spread the subnets over, for example [\"eu-west-1a\", \"eu-west-1b\", \"eu-west-1c\"]. Each zone gets one public, one private and one isolated subnet and its own NAT gateway"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 6 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must list between 2 and 6 distinct zones."
  }
}

variable "logs_kms_key_arn" {
  description = "Key that encrypts the VPC flow log group"
  type        = string
}

variable "flow_log_retention_days" {
  description = "Days to keep VPC flow logs"
  type        = number
  default     = 365
}

variable "gateway_endpoint_services" {
  description = "Gateway endpoints to create, attached to the private and isolated route tables. Allowed: s3, dynamodb"
  type        = set(string)
  default     = ["s3"]

  validation {
    condition     = length(setsubtract(var.gateway_endpoint_services, ["s3", "dynamodb"])) == 0
    error_message = "gateway_endpoint_services may only contain s3 and dynamodb."
  }
}

variable "interface_endpoint_services" {
  description = "Interface endpoints to create in the private subnets, by service name without the com.amazonaws.<region> prefix, for example [\"ecr.api\", \"ecr.dkr\", \"logs\", \"secretsmanager\"]"
  type        = set(string)
  default     = []
}
