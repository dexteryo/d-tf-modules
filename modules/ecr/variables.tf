variable "name" {
  description = "Repository name, for example ordering-agent"
  type        = string
}

variable "namespace" {
  description = "Optional path in front of the name, for example example-org. The repository is <namespace>/<name>"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "create_kms_key" {
  description = "Create a key for the images through the kms module. Set false and pass kms_key_arn to use a key you own; the choice cannot depend on a value known only after apply"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts the images when create_kms_key is false"
  type        = string
  default     = null
}

variable "mutable_image_tags" {
  description = "Allow a tag to be pushed again. Keep false: deploys reference digests and every build gets its own tag"
  type        = bool
  default     = false
}

variable "scan_on_push" {
  description = "Run the ECR image scan on every push"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Delete the repository even when it still holds images. Only for throwaway repositories"
  type        = bool
  default     = false
}

variable "pull_account_ids" {
  description = "AWS account ids, besides this one, whose roles may pull the images. Empty creates no repository policy"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.pull_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "pull_account_ids must be 12-digit AWS account ids."
  }
}

variable "enable_lifecycle_policy" {
  description = "Expire old images according to untagged_expiry_days and max_tagged_images"
  type        = bool
  default     = true
}

variable "untagged_expiry_days" {
  description = "Days an untagged image is kept after it was pushed"
  type        = number
  default     = 7
}

variable "max_tagged_images" {
  description = "Number of tagged images to keep; older ones expire"
  type        = number
  default     = 30
}
