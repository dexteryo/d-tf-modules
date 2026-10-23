output "kms_key_arn" {
  description = "ARN of the key"
  value       = aws_kms_key.this.arn
}

output "kms_key_id" {
  description = "ID of the key"
  value       = aws_kms_key.this.key_id
}

output "kms_alias_name" {
  description = "Alias of the key, alias/<name>-<environment>[-<name_suffix>]"
  value       = aws_kms_alias.this.name
}

output "kms_alias_arn" {
  description = "ARN of the alias"
  value       = aws_kms_alias.this.arn
}

output "key_rotation_enabled" {
  description = "Whether automatic key rotation is on; always true"
  value       = aws_kms_key.this.enable_key_rotation
}
