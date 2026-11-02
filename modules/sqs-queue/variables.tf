variable "name" {
  description = "Workload name. The queue is named <name>-<environment>[-<name_suffix>] and its dead-letter queue adds -dlq"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example integration, staging, production)"
  type        = string
}

variable "name_suffix" {
  description = "Optional last part of the name, for example jobs"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for every resource, usually the all_tags output of the tags module"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts both queues. Producers and consumers need kms:GenerateDataKey and kms:Decrypt on it"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "How long a received message stays hidden. Set it above the consumer's timeout"
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long the queue and the dead-letter queue keep a message. The default is 14 days, the SQS maximum"
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "Receives of one message before SQS moves it to the dead-letter queue"
  type        = number
  default     = 5

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count must be between 1 and 1000."
  }
}

variable "alarm_actions" {
  description = "ARNs notified when the dead-letter queue holds a message, usually the topic_arn of the sns-topic module. Empty keeps the alarm without a notification"
  type        = list(string)
  default     = []
}
