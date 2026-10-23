variable "name" {
  description = "Workload name. The alias is alias/<name>-<environment>[-<name_suffix>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production). Leave empty for keys shared by all environments"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Optional last part of the alias, for example app or tokens when one workload has several keys"
  type        = string
  default     = ""
}

variable "description" {
  description = "What the key encrypts"
  type        = string
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "deletion_window_in_days" {
  description = "Days AWS waits before deleting the key after it is scheduled for deletion (7 to 30)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "enable_iam_policy_delegation" {
  description = "Let IAM identity policies in this account grant use of the key (root principal gets kms:*). Turn it off to restrict use to the principals listed below"
  type        = bool
  default     = true
}

variable "management_principals" {
  description = "Principal ARNs that may administer the key but not use it. The account root administers the key when enable_iam_policy_delegation is off"
  type        = list(string)
  default     = []
}

variable "encrypt_principals" {
  description = "Principal ARNs that may encrypt, decrypt and generate data keys"
  type        = list(string)
  default     = []
}

variable "decrypt_principals" {
  description = "Principal ARNs that may only decrypt"
  type        = list(string)
  default     = []
}

variable "service_grants" {
  description = "AWS services that may use the key. actions defaults to encrypt, decrypt and generate data key. condition narrows the grant, for example to one log group"
  type = list(object({
    sid     = string
    service = string
    actions = optional(list(string), ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"])
    condition = optional(object({
      test     = string
      variable = string
      values   = list(string)
    }))
  }))
  default = []
}

variable "additional_statements" {
  description = "Extra key policy statements, as objects in IAM JSON policy shape"
  type        = any
  default     = []
}
