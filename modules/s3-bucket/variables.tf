variable "name" {
  description = "Workload name. The bucket is named <name>-<environment>[-<name_suffix>][-<account id>]"
  type        = string
}

variable "environment" {
  description = "Deployment environment, for example integration or production. Leave empty for a bucket shared by all environments"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Optional last part of the name, for example documents or uploads when one workload has several buckets"
  type        = string
  default     = ""
}

variable "append_account_id" {
  description = "Append the account ID to the name. Bucket names are global, so this keeps the same module call valid in every account"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts the objects"
  type        = string
}

variable "object_lock_retention_days" {
  description = "Compliance-mode Object Lock default retention in days. Null leaves Object Lock off. Compliance mode cannot be shortened or removed by anyone, including the account root, so keep it short outside production"
  type        = number
  default     = null

  validation {
    condition     = var.object_lock_retention_days == null || try(var.object_lock_retention_days >= 1, false)
    error_message = "object_lock_retention_days must be null or at least 1."
  }
}

variable "cloudfront_distribution_arn" {
  description = "Distribution allowed to read objects through origin access control. Null for buckets CloudFront never serves"
  type        = string
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Days before superseded object versions expire. Ignored while Object Lock is on, because locked versions cannot be removed"
  type        = number
  default     = 90
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which an unfinished multipart upload is aborted"
  type        = number
  default     = 7
}
